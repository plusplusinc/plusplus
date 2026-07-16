import Foundation
import AVFoundation

/// The voice-cue setting (Settings tray → VOICE CUES): not a toggle but
/// a three-way mode, per Dave — every exercise start, refreshers only,
/// or off. Default OFF: a voice that starts talking unasked is a
/// surprise, so speaking is an opt-in, same spirit as the Health and
/// calendar asks.
enum VoiceCueMode: String, CaseIterable {
    /// Speak at the start of every exercise block.
    case always
    /// Speak only when the exercise is new to you or you haven't done
    /// it in a while (`refresherWindowDays`) — the "remind me how this
    /// goes" setting.
    case refresher
    case off

    static let key = "voiceCueMode"

    static var current: VoiceCueMode {
        VoiceCueMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .off
    }

    /// "Hasn't been done in a while" = a month.
    static let refresherWindowDays = 30
}

/// Speaks a built-in exercise's form cues (`FormCues`) as the exercise
/// starts in a live session — driven from ActiveSessionView's
/// `activeExerciseKey`, the same identity the GPS meter re-bases on, so
/// a block announces once and its later rounds stay quiet.
///
/// Audio behavior: `.playback` so the silent switch can't mute a cue
/// mid-gym (an apparently dead setting is the broken-feature read),
/// `.duckOthers` so music dips instead of stopping, and
/// `.interruptSpokenAudioAndMixWithOthers` so a podcast pauses rather
/// than talking over the cue. The session deactivates with
/// `.notifyOthersOnDeactivation` when speech ends so ducked audio
/// comes back up. No `audio` background mode: with the app backgrounded
/// the cue simply doesn't sound, which is fine for a glance-at-the-
/// phone feature (v1; the watch has its own haptic language).
///
/// ALL audio work — activation, speaking, deactivation — runs on one
/// private serial queue: `AVAudioSession.setActive` is a blocking IPC
/// to mediaserverd (up to hundreds of ms on first activation) and the
/// announce trigger fires in the same render pass that animates the
/// SWITCH screen in, so none of it may run on the main thread (the
/// "always feels fast" law). The queue also makes cue replacement
/// race-free: end-of-utterance bookkeeping hops onto it, so it is
/// ordered AFTER the replacement `speak`, and deactivation is decided
/// by an outstanding-utterance count — never by delegate delivery
/// timing, which differs across iOS releases.
final class VoiceCueSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceCueSpeaker()

    private let queue = DispatchQueue(label: "com.davidcole.plusplus.voicecues")
    /// Queue-confined after init (delegate assignment precedes any use).
    private let synthesizer = AVSpeechSynthesizer()

    /// Utterances handed to the synthesizer whose end callback hasn't
    /// been processed yet — queue-confined. The session deactivates
    /// only at zero, so ducked music comes back exactly once, and a
    /// replacement cue can never have the session pulled out from
    /// under it by its predecessor's cancellation.
    private var outstanding = 0

    /// Exercise blocks already announced this app run — keyed on
    /// session identity + block, so a view remount (overview sheet,
    /// pause, reopening from the Live Activity) can't re-announce.
    /// Main-confined: `announce` is only called from the session view.
    /// In-memory on purpose: a relaunch mid-workout re-announces the
    /// current exercise once, a serviceable "where was I".
    private var announcedKeys: Set<String> = []

    /// No audio under UI tests (the WorkoutActivityController gate).
    private let disabled = CommandLine.arguments.contains("--uitest-reset")

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks "«name». «cues»" once per dedup key. Quiet whenever the
    /// mode says so or the catalog has no line for the name (customs
    /// and the deliberately-silent cardio) — the audio session is only
    /// touched when there is something to say. `isRefresher` is the
    /// caller's model knowledge (new-to-you, or not done in a month);
    /// it's an autoclosure so the history scan only runs in refresher
    /// mode.
    func announce(exerciseNamed name: String, dedupKey: String, isRefresher: @autoclosure () -> Bool) {
        let mode = VoiceCueMode.current
        guard !disabled, mode != .off else { return }
        guard !announcedKeys.contains(dedupKey) else { return }
        guard let cues = FormCues.line(for: name) else { return }
        if mode == .refresher, !isRefresher() { return }
        announcedKeys.insert(dedupKey)

        let utterance = AVSpeechUtterance(string: "\(name). \(cues)")
        utterance.preUtteranceDelay = 0.1
        queue.async { [self] in
            let audio = AVAudioSession.sharedInstance()
            try? audio.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try? audio.setActive(true)
            outstanding += 1
            // A rapid jump (session overview) replaces the current cue —
            // two voices at once is worse than a clipped sentence. The
            // cancelled cue's bookkeeping lands on this queue AFTER this
            // block, so the count can't dip to zero mid-replacement no
            // matter when the delegate callback is delivered.
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            synthesizer.speak(utterance)
        }
    }

    /// Cuts speech immediately (finish, discard, leaving the screen).
    /// When nothing is speaking it still sweeps for a session left
    /// active by an earlier failed deactivation — ducked music must
    /// never outlive the workout.
    func stop() {
        guard !disabled else { return }
        queue.async { [self] in
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate) // bookkeeping deactivates
            } else {
                deactivateIfIdle()
            }
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    // Delivery thread and timing are unspecified (didCancel has been
    // observed arriving synchronously from inside stopSpeaking on some
    // iOS releases) — both handlers do nothing but hop onto the queue.

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        queue.async { [self] in utteranceEnded() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        queue.async { [self] in utteranceEnded() }
    }

    /// Queue-confined.
    private func utteranceEnded() {
        outstanding = max(0, outstanding - 1)
        deactivateIfIdle()
    }

    /// Queue-confined. Deactivation can throw while the output IO is
    /// still winding down (the "session is busy" OSStatus); a swallowed
    /// failure would leave the user's music ducked for good, so it
    /// retries on a short backoff — re-checking idleness each attempt,
    /// since a new cue may have started in the meantime.
    private func deactivateIfIdle(attempt: Int = 0) {
        guard outstanding == 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            guard attempt < 3 else { return }
            queue.asyncAfter(deadline: .now() + 0.4) { [self] in
                deactivateIfIdle(attempt: attempt + 1)
            }
        }
    }
}

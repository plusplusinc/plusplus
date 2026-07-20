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

/// The chosen synthesis voice, stored as the voice IDENTIFIER; empty or
/// unset = the system's default voice for the device language. A voice
/// later deleted from the device falls back to the default silently.
///
/// What Apple exposes (`AVSpeechSynthesisVoice.speechVoices()`): every
/// INSTALLED system voice, per language, in three quality tiers —
/// compact (always present), Enhanced and Premium (downloaded by the
/// user in iOS Settings → Accessibility → Spoken Content → Voices).
/// The same name ships at several tiers, so tiered variants are
/// distinct picker entries labeled by quality. Filtered out: novelty
/// voices (Bells, Bubbles…) — a joke voice coaching form undermines
/// the feature — and Personal Voice, which needs its own authorization
/// flow (a fine follow-up, not v1). Siri's own voices are not exposed
/// to apps at all.
enum VoiceCueVoice {
    static let key = "voiceCueVoiceIdentifier"

    static var selectedIdentifier: String? {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// The resolved voice for an utterance; nil = system default.
    static var selected: AVSpeechSynthesisVoice? {
        selectedIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
    }

    /// One pickable voice. `id` is the AVSpeech identifier; "" is the
    /// system-default sentinel (it round-trips through the same stored
    /// string).
    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
    }

    /// English voices installed on the device (the cues are English),
    /// system default first, then name-sorted. Enumerating the system
    /// voice list has real cost — call once per tray appearance, not
    /// per render.
    static func options() -> [Option] {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix("en")
                && !voice.voiceTraits.contains(.isNoveltyVoice)
                && !voice.voiceTraits.contains(.isPersonalVoice)
        }
        // Typed intermediate: a multi-statement map closure in a chain
        // leaves the element type uninferred at the sorted step.
        let named: [Option] = voices.map { voice in
            var label = voice.name
            switch voice.quality {
            case .enhanced: label += " · Enhanced"
            case .premium: label += " · Premium"
            default: break
            }
            return Option(id: voice.identifier, label: label)
        }
        let sorted = named.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        return [Option(id: "", label: "System default")] + sorted
    }
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
/// shared serial queue (`WorkoutAudioSession`'s, also used by
/// `CountdownCue`): `AVAudioSession.setActive` is a blocking IPC to
/// mediaserverd (up to hundreds of ms on first activation) and the
/// announce trigger fires in the same render pass that animates the
/// SWITCH screen in, so none of it may run on the main thread (the
/// "always feels fast" law). The queue also makes cue replacement
/// race-free: end-of-utterance bookkeeping hops onto it, so it is
/// ordered AFTER the replacement `speak`, and session activation is
/// refcounted in `WorkoutAudioSession` (a shared hold count across both
/// cue sources) — never decided by delegate delivery timing, which
/// differs across iOS releases.
final class VoiceCueSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceCueSpeaker()

    /// Shared with CountdownCue via WorkoutAudioSession, so the two audio
    /// sources own one process session and can't race its activation.
    private var queue: DispatchQueue { WorkoutAudioSession.shared.queue }
    /// Queue-confined after init (delegate assignment precedes any use).
    private let synthesizer = AVSpeechSynthesizer()

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
        speak("\(name). \(cues)")
    }

    /// Speaks a short sample so a just-picked voice can be judged
    /// without starting a workout — the settings tray calls this on
    /// voice selection. Real cue content, so the sample sounds like
    /// the feature.
    func preview() {
        guard !disabled else { return }
        speak("Squat. \(FormCues.line(for: "Squat") ?? "")")
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.preUtteranceDelay = 0.1
        utterance.voice = VoiceCueVoice.selected
        queue.async { [self] in
            // Take the shared hold BEFORE cancelling any current cue, so a
            // replacement (a rapid session-overview jump) can't dip the hold
            // count to zero mid-swap — the cancelled cue's release lands on
            // this queue AFTER this block. Two voices at once is worse than a
            // clipped sentence.
            WorkoutAudioSession.shared.hold { audio in
                try? audio.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
                )
            }
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
                synthesizer.stopSpeaking(at: .immediate)
            }
            // Force the shared session down — the workout is ending or the
            // screen is leaving, so any outstanding hold is being abandoned.
            WorkoutAudioSession.shared.sweep()
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

    /// Queue-confined. Drops this utterance's shared hold; the session
    /// deactivates once no cue (voice or countdown) holds it.
    private func utteranceEnded() {
        WorkoutAudioSession.shared.release()
    }
}

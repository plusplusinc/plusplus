import Foundation
import AVFoundation

/// One source of truth for the voice-guidance setting's storage key
/// (the WeightUnitSetting pattern). Default OFF: a voice that starts
/// talking unasked is a surprise, so the feature is an opt-in in
/// Settings → VOICE, same spirit as the Health and calendar asks.
enum FormGuidanceSetting {
    static let key = "formGuidanceVoice"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}

/// Speaks a built-in exercise's form cues (`FormCues`) as the exercise
/// starts in a live session — driven from ActiveSessionView's
/// `activeExerciseKey`, the same identity the GPS meter re-bases on, so
/// a block announces once and its later rounds stay quiet.
///
/// Audio behavior: `.playback` so the silent switch can't mute a cue
/// mid-gym (an apparently dead toggle is the broken-feature read),
/// `.duckOthers` so music dips instead of stopping, and
/// `.interruptSpokenAudioAndMixWithOthers` so a podcast pauses rather
/// than talking over the cue. The session deactivates with
/// `.notifyOthersOnDeactivation` when speech ends so ducked audio
/// comes back up. No `audio` background mode: with the app backgrounded
/// the cue simply doesn't sound, which is fine for a glance-at-the-
/// phone feature (v1; the watch has its own haptic language).
@MainActor
final class FormGuidanceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = FormGuidanceSpeaker()

    private let synthesizer = AVSpeechSynthesizer()

    /// Exercise blocks already announced this app run — keyed on
    /// session identity + block, so a view remount (overview sheet,
    /// pause, reopening from the Live Activity) can't re-announce.
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
    /// setting is off or the catalog has no line for the name (customs)
    /// — the audio session is only touched when there is something to
    /// say.
    func announce(exerciseNamed name: String, dedupKey: String) {
        guard !disabled, FormGuidanceSetting.isEnabled else { return }
        guard !announcedKeys.contains(dedupKey) else { return }
        guard let cues = FormCues.line(for: name) else { return }
        announcedKeys.insert(dedupKey)

        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try? audio.setActive(true)

        // A rapid jump (session overview) replaces the current cue —
        // two voices at once is worse than a clipped sentence.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: "\(name). \(cues)")
        utterance.preUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    /// Cuts speech immediately (finish, discard, leaving the screen).
    /// The didCancel callback releases the audio session.
    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    // Callbacks arrive off-main, so they use only their parameters —
    // deactivating the session is what un-ducks the user's music.

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Self.releaseAudioSession(after: synthesizer)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Self.releaseAudioSession(after: synthesizer)
    }

    private nonisolated static func releaseAudioSession(after synthesizer: AVSpeechSynthesizer) {
        // A replacement utterance may already be queued (the jump path)
        // — keep the session alive for it.
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

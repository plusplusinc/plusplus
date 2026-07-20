import Foundation
import AVFoundation

/// The single owner of the process `AVAudioSession` for PlusPlus's in-workout
/// audio cues. Both `VoiceCueSpeaker` (speech) and `CountdownCue` (tones)
/// route activation through here, so the shared session stays active while
/// EITHER is sounding and deactivates only once BOTH are idle.
///
/// Two independent owners each calling `setActive(true/false)` on the same
/// shared session raced each other: the countdown go-tone fires at the exact
/// instant the next exercise begins and its voice cue speaks, so the tone's
/// deferred `setActive(false)` could tear the session out from under a
/// mid-sentence cue (and a dropped decrement in one owner left the user's
/// music ducked with no sweep). One refcounted owner removes the race.
///
/// ALL session mutation — and each caller's own playback — runs on this one
/// shared serial `queue`, so activation always precedes playback on the same
/// serial line and the two sources can't interleave `setActive` calls.
/// Callers bracket their audio work with `hold(configure:)` (activate +
/// refcount) and `release(after:)` (deferred deactivate at zero); `sweep()`
/// force-clears a session left active by a failed or interrupted cue, or a
/// workout ending.
final class WorkoutAudioSession {
    static let shared = WorkoutAudioSession()

    /// The one serial queue all cue audio work runs on. Callers use THIS
    /// queue for their `synth.speak` / `player.play` too.
    let queue = DispatchQueue(label: "com.davidcole.plusplus.audio")

    /// Live holds across BOTH cue sources — queue-confined.
    private var holds = 0
    /// Bumped on every hold; a deferred release only deactivates if it is
    /// still the latest, so back-to-back cues don't thrash the session.
    private var generation = 0

    private init() {}

    /// Configure the category and activate, taking a hold. Queue-confined:
    /// call from inside a `queue.async {}` block, before playback, so the
    /// session is live the instant this returns.
    func hold(configure: (AVAudioSession) -> Void) {
        let audio = AVAudioSession.sharedInstance()
        configure(audio)
        try? audio.setActive(true)
        holds += 1
        generation += 1
    }

    /// Drop a hold; deactivate once the last one clears. `after` defers the
    /// deactivate so a run of cues a beat apart (the 3·2·1·go beeps, or a
    /// replaced voice cue) keeps the session up instead of thrashing the
    /// user's music. Queue-confined.
    func release(after seconds: Double = 0) {
        holds = max(0, holds - 1)
        guard seconds > 0 else { deactivateIfIdle(); return }
        let g = generation
        queue.asyncAfter(deadline: .now() + seconds) { [self] in
            guard g == generation else { return } // a newer cue superseded this
            deactivateIfIdle()
        }
    }

    /// Force the session down regardless of the count — for a workout ending
    /// or a cue cut short, where any outstanding holds are being abandoned.
    /// Queue-confined.
    func sweep() {
        holds = 0
        deactivateIfIdle()
    }

    /// Queue-confined. Deactivation can throw while the output IO is still
    /// winding down (the "session is busy" OSStatus); a swallowed failure
    /// would leave the user's music ducked for good, so it retries on a
    /// short backoff, re-checking idleness each attempt.
    private func deactivateIfIdle(attempt: Int = 0) {
        guard holds == 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            guard attempt < 3 else { return }
            queue.asyncAfter(deadline: .now() + 0.4) { [self] in deactivateIfIdle(attempt: attempt + 1) }
        }
    }
}

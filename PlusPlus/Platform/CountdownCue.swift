import Foundation
import AVFoundation

/// The countdown-cue setting (Settings tray → COUNTDOWN CUES): a plain
/// on/off. Default ON — unlike the voice cues (an unasked talking coach is a
/// surprise, so those opt in), a rest countdown beep is a conventional,
/// expected timer affordance, so it ships on and the user can silence it.
enum CountdownCueSetting {
    static let key = "countdownCuesEnabled"

    /// Unset reads as ON, so the stored `false` from an explicit toggle-off
    /// is the only way it's silent — must match the `@AppStorage` default.
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Plays the rest/transition countdown tones: a short tick on each of the
/// last three seconds, and a distinct higher tone as the next exercise
/// begins. The app's second audio source after `VoiceCueSpeaker`; both drive
/// activation through the shared `WorkoutAudioSession` so they can't race the
/// shared AVAudioSession (the go-tone fires the very instant the next
/// exercise's voice cue speaks).
///
/// Tones are sine waves synthesized in memory (no bundled assets) and played
/// through `AVAudioPlayer`. All work runs on `WorkoutAudioSession`'s serial
/// queue: `setActive` is a blocking mediaserverd IPC and the tick fires in
/// the rest screen's per-second render pass (the "always feels fast" law).
/// The session is held per beep and released with a defer, so the 3·2·1·go
/// run (tones ~1 s apart) keeps it up instead of thrashing the user's music
/// between beeps. A failed `play()` releases its hold at once, and `stop()`
/// sweeps at workout end, so a dropped or interrupted beep can never strand
/// the session active (ducking the user's music for good). No `audio`
/// background mode: backgrounded, the beep simply doesn't sound (v1; the
/// watch keeps its haptics). Inert under UI tests.
final class CountdownCue: NSObject, AVAudioPlayerDelegate {
    static let shared = CountdownCue()

    /// Shared with VoiceCueSpeaker (one owner of the process audio session).
    private var queue: DispatchQueue { WorkoutAudioSession.shared.queue }
    private let disabled = CommandLine.arguments.contains("--uitest-reset")

    /// Which tone to play. Resolved to a player ON the queue so the lazy
    /// tone synthesis never runs on the main thread.
    private enum Tone { case tick, start }

    /// Built once (the tone data is fixed) and reused; queue-confined. The
    /// start tone is higher and a touch longer so "go" is unmistakably not
    /// another countdown tick.
    private lazy var tickPlayer = Self.makePlayer(frequency: 784, duration: 0.09)
    private lazy var startPlayer = Self.makePlayer(frequency: 1175, duration: 0.16)

    private override init() { super.init() }

    /// A last-three-seconds countdown tick (call at remaining == 3, 2, 1).
    func tick() { play(.tick) }

    /// The higher "go" tone as the next exercise/set begins.
    func start() { play(.start) }

    /// Sweep any active session at workout end (wired next to
    /// `VoiceCueSpeaker.stop()`); idempotent with the voice cue's own sweep.
    func stop() {
        guard !disabled else { return }
        queue.async { [self] in
            tickPlayer?.stop()
            startPlayer?.stop()
            WorkoutAudioSession.shared.sweep()
        }
    }

    private func play(_ tone: Tone) {
        guard !disabled, CountdownCueSetting.isEnabled else { return }
        queue.async { [self] in
            guard let player = (tone == .tick ? tickPlayer : startPlayer) else { return }
            WorkoutAudioSession.shared.hold { audio in
                try? audio.setCategory(.playback, options: [.duckOthers])
            }
            player.delegate = self
            player.currentTime = 0
            // A failed start never fires audioPlayerDidFinishPlaying, so drop
            // the hold now or the session stays active (the user's music
            // ducked with no recovery).
            if !player.play() {
                WorkoutAudioSession.shared.release()
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        queue.async {
            // Defer so the 3·2·1·go tones (about a second apart) don't
            // duck-and-restore the user's music between each beep.
            WorkoutAudioSession.shared.release(after: 1.5)
        }
    }

    // MARK: - Tone synthesis (no bundled assets)

    private static func makePlayer(frequency: Double, duration: Double) -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(data: wavTone(frequency: frequency, duration: duration))
        player?.prepareToPlay()
        return player
    }

    /// A mono 16-bit PCM WAV of a sine tone, built in memory, with short
    /// raised-cosine fades so the onset/offset don't click.
    private static func wavTone(frequency: Double, duration: Double, sampleRate: Double = 44_100) -> Data {
        let frameCount = Int(duration * sampleRate)
        let fade = max(1, Int(0.006 * sampleRate)) // ~6 ms in/out
        let peak = 0.6 * Double(Int16.max)
        var samples = [Int16]()
        samples.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let envelope: Double
            if i < fade { envelope = Double(i) / Double(fade) }
            else if i >= frameCount - fade { envelope = Double(frameCount - i) / Double(fade) }
            else { envelope = 1 }
            let value = sin(2 * .pi * frequency * t) * peak * envelope
            samples.append(Int16(value.rounded().clamped(to: Double(Int16.min)...Double(Int16.max))))
        }
        return wavContainer(samples: samples, sampleRate: Int(sampleRate))
    }

    private static func wavContainer(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let dataSize = samples.count * MemoryLayout<Int16>.size
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        put32(16)                          // PCM fmt chunk size
        put16(1)                           // format = PCM
        put16(1)                           // channels = mono
        put32(UInt32(sampleRate))
        put32(UInt32(sampleRate * 2))      // byte rate (mono, 16-bit)
        put16(2)                           // block align
        put16(16)                          // bits per sample
        data.append(contentsOf: Array("data".utf8))
        put32(UInt32(dataSize))
        for sample in samples { put16(UInt16(bitPattern: sample)) }
        return data
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

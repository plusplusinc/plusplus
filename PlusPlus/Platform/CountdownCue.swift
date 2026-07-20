import Foundation
import AVFoundation

/// The countdown-cue setting (Settings tray → COUNTDOWN CUES): a plain
/// on/off. Default OFF — like the voice cues, an app that starts making
/// noise unasked is a surprise, so the beeps are opt-in.
enum CountdownCueSetting {
    static let key = "countdownCuesEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// Plays the rest/transition countdown tones: a short tick on each of the
/// last three seconds, and a distinct higher tone as the next exercise
/// begins. The app's second audio source after `VoiceCueSpeaker`, and it
/// mirrors that class's session discipline exactly:
///
/// `.playback` so the silent switch can't mute the cue mid-gym (a dead
/// setting reads as broken), `.duckOthers` so music dips instead of
/// stopping. ALL audio work — activation, playback, deactivation — runs on
/// one private serial queue, because `AVAudioSession.setActive` is a
/// blocking IPC to mediaserverd and the tick fires inside the rest screen's
/// per-second render pass (the "always feels fast" law). Deactivation is
/// decided by an outstanding-player count and DEFERRED, so the 3·2·1·go
/// tones (about a second apart) don't duck-and-restore the user's music
/// between each beep. No `audio` background mode: backgrounded, the beep
/// simply doesn't sound (v1; the watch keeps its own haptics). Inert under
/// UI tests, the same gate as the other system surfaces.
final class CountdownCue: NSObject, AVAudioPlayerDelegate {
    static let shared = CountdownCue()

    private let queue = DispatchQueue(label: "com.davidcole.plusplus.countdowncue")
    private let disabled = CommandLine.arguments.contains("--uitest-reset")

    /// Which tone to play. Resolved to a player ON the queue so the lazy
    /// tone synthesis never runs on the main thread.
    private enum Tone { case tick, start }

    /// Built once (the tone data is fixed) and reused; queue-confined. The
    /// start tone is higher and a touch longer so "go" is unmistakably not
    /// another countdown tick.
    private lazy var tickPlayer = Self.makePlayer(frequency: 784, duration: 0.09)
    private lazy var startPlayer = Self.makePlayer(frequency: 1175, duration: 0.16)

    /// Players handed to the system whose finish callback hasn't landed yet
    /// — queue-confined. The session deactivates only at zero so ducked
    /// music comes back exactly once.
    private var outstanding = 0

    /// Bumped on every beep; a deferred deactivate only proceeds if it is
    /// still the latest, so an earlier tick's timer can't tear the session
    /// down in the gap before the next tick in the same 3·2·1·go run.
    private var generation = 0

    private override init() { super.init() }

    /// A last-three-seconds countdown tick (call at remaining == 3, 2, 1).
    func tick() { play(.tick) }

    /// The higher "go" tone as the next exercise/set begins.
    func start() { play(.start) }

    private func play(_ tone: Tone) {
        guard !disabled, CountdownCueSetting.isEnabled else { return }
        queue.async { [self] in
            guard let player = (tone == .tick ? tickPlayer : startPlayer) else { return }
            let audio = AVAudioSession.sharedInstance()
            try? audio.setCategory(.playback, options: [.duckOthers])
            try? audio.setActive(true)
            outstanding += 1
            generation += 1
            player.delegate = self
            player.currentTime = 0
            player.play()
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        queue.async { [self] in
            outstanding = max(0, outstanding - 1)
            scheduleDeactivate()
        }
    }

    /// Defer deactivation so a run of beeps a second apart keeps the session
    /// active across the whole 3·2·1·go sequence instead of thrashing the
    /// user's music up and down.
    private func scheduleDeactivate() {
        let g = generation
        queue.asyncAfter(deadline: .now() + 1.5) { [self] in
            guard g == generation else { return } // a newer beep superseded this
            deactivateIfIdle()
        }
    }

    /// Queue-confined. Deactivation can throw while the output IO is still
    /// winding down (the "session is busy" OSStatus); a swallowed failure
    /// would leave the user's music ducked for good, so it retries on a
    /// short backoff, re-checking idleness each attempt.
    private func deactivateIfIdle(attempt: Int = 0) {
        guard outstanding == 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            guard attempt < 3 else { return }
            queue.asyncAfter(deadline: .now() + 0.4) { [self] in deactivateIfIdle(attempt: attempt + 1) }
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

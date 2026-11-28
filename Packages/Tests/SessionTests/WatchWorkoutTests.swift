import Foundation
import Health
import Testing
@testable import Session
@testable import WorkoutStore

/// The workout on the Watch: its taps, what it keeps on disk, and what it plays on the wrist.
@MainActor
@Suite("Watch workout")
struct WatchWorkoutTests {
    final class Recorder {
        var haptics: [WatchHaptic] = []
        var written: Data?
    }

    static func watch(_ recorder: Recorder, at date: Date) -> WatchWorkout {
        WatchWorkout(
            mirror: .unavailable,
            saved: nil,
            write: { recorder.written = $0 },
            haptic: { recorder.haptics.append($0) },
            now: { date },
        )
    }

    @Test("Alone, a workout opens on its first set's \"Start in\", with no key")
    func aloneStartsIn() throws {
        let recorder = Recorder()
        let start = WatchFixture.start
        let watch = Self.watch(recorder, at: start)
        watch.runAlone(WatchFixture.demo)
        let face = try #require(watch.live?.watchFace(at: start + 1))
        #expect(face.middle == .count(label: "Start in", time: "0:04"))
        #expect(face.key == nil)
    }

    @Test("A set logged on the wrist shows at once, plays, and is kept for a relaunch")
    func logOnWrist() throws {
        let recorder = Recorder()
        let start = WatchFixture.start
        let watch = Self.watch(recorder, at: start + 10)
        watch.runAlone(WatchFixture.demo)
        let set = try #require(watch.live?.currentSet)
        watch.tap(.log(set))
        #expect(watch.live?.workoutSession.sets.count == 1)
        #expect(recorder.haptics == [.setLogged])
        let saved = try #require(recorder.written)
        let relaunched = WatchWorkout(
            mirror: .unavailable,
            saved: saved,
            write: { _ in },
            haptic: { _ in },
            now: { start + 11 },
        )
        #expect(relaunched.live?.workoutSession.sets.count == 1)
    }

    @Test("Finish on the wrist shows the finished page's numbers")
    func finishOnWrist() throws {
        let recorder = Recorder()
        let start = WatchFixture.start
        let watch = Self.watch(recorder, at: start + 10)
        watch.runAlone(WatchFixture.demo)
        let set = try #require(watch.live?.currentSet)
        watch.tap(.log(set))
        watch.tap(.finish)
        let ended = try #require(watch.ended)
        #expect(ended.finished)
        #expect(ended.sets == 1)
        #expect(recorder.haptics.last == .finished)
    }
}

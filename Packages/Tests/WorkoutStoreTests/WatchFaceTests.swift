import Foundation
import Testing
@testable import WorkoutStore

/// The Watch's set page, read from each fixture the boards draw, in US English.
@Suite("Watch face")
struct WatchFaceTests {
    static let locale = Locale(identifier: "en_US")

    static func face(_ fixture: WatchFixture) throws -> WatchFace {
        let (live, now) = fixture.live
        return try #require(live.watchFace(at: now, locale: locale))
    }

    @Test("An exercise coming up counts \"Start in\" with no key")
    func startIn() throws {
        let face = try Self.face(.startIn)
        #expect(face.name == "Barbell bench press")
        #expect(face.dot == .active)
        #expect(face.bars == [[.current], [.toDo], [.toDo]])
        #expect(face.caption == "Set 1 of 3")
        #expect(face.middle == .count(label: "Start in", time: "0:05"))
        #expect(face.key == nil)
    }

    @Test("A set up shows its numbers and Log set")
    func set() throws {
        let face = try Self.face(.set)
        #expect(face.caption == "Set 1 of 3")
        #expect(face.middle == .figures([
            PlanFigure(number: "5", unit: "reps"), PlanFigure(number: "45", unit: "lb"),
        ]))
        #expect(face.key == .log("Log set"))
    }

    @Test("A rest counts down after the set it follows, which reads done")
    func resting() throws {
        let face = try Self.face(.resting)
        #expect(face.bars == [[.done], [.toDo], [.toDo]])
        #expect(face.caption == "Set 1 of 3 done")
        #expect(face.middle == .count(label: "Rest", time: "0:28"))
        guard case let .rest(fill) = face.key else {
            Issue.record("Expected Skip and +15, got \(String(describing: face.key))")
            return
        }
        #expect(abs(fill - 32.0 / 60) < 0.02)
    }

    @Test("After the last set: the count of sets, the time, and Finish")
    func allLogged() throws {
        let face = try Self.face(.allLogged)
        #expect(face.name == "Pull-up")
        #expect(face.dot == .done)
        #expect(face.bars == [[.done], [.done], [.done]])
        #expect(face.caption == "Set 3 of 3 done")
        guard case let .allLogged(count, detail) = face.middle else {
            Issue.record("Expected all logged, got \(face.middle)")
            return
        }
        #expect(count == "9 of 9")
        #expect(detail.hasPrefix("sets done in "))
        #expect(face.key == .finish)
    }

    @Test("A timed set counts its own time, with Log early")
    func timed() throws {
        let face = try Self.face(.timed)
        #expect(face.name == "Plank")
        #expect(face.middle == .timed(time: "0:42", of: "of 1:00"))
        guard case let .logEarly(fill) = face.key else {
            Issue.record("Expected Log early, got \(String(describing: face.key))")
            return
        }
        #expect(abs(fill - 18.0 / 60) < 0.02)
    }

    @Test("A set done a side at a time: a pair of bars a set, and the side named")
    func perSide() throws {
        let face = try Self.face(.perSide)
        #expect(face.name == "Dumbbell row")
        #expect(face.bars == [[.done, .done], [.current, .toDo], [.toDo, .toDo]])
        #expect(face.caption == "Set 2 of 3 · Left")
        #expect(face.middle == .figures([
            PlanFigure(number: "10", unit: "reps"), PlanFigure(number: "25", unit: "lb"),
        ]))
    }

    @Test("In a superset: rounds, not sets")
    func superset() throws {
        let face = try Self.face(.superset)
        #expect(face.name == "Push-up")
        #expect(face.bars == [[.done], [.current], [.toDo]])
        #expect(face.caption == "Round 2 of 3")
    }

    @Test("Paused: the dot goes quiet, the caption says so, and the key is Continue")
    func paused() throws {
        let face = try Self.face(.paused)
        #expect(face.dot == .quiet)
        #expect(face.caption == "Set 2 of 3 · Paused")
        #expect(face.key == .resume)
        #expect(face.isQuiet)
    }

    @Test("No workout in progress has no set page")
    func notStarted() {
        var (live, now) = WatchFixture.set.live
        live.workoutSession = live.finishing(at: now)
        #expect(live.watchFace(at: now, locale: Self.locale) == nil)
    }
}

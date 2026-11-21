import Foundation
import Testing
@testable import WorkoutStore

/// The key on a timed set: "Start now" during "Starts in", "Log early" with +15 s while it
/// counts, and the log its end makes, all from the phase.
@Suite("Workout key on a timed set")
struct WorkoutKeyCountTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// A workout on two planks, the first of two sets, its count begun at `start`.
    private static func live() throws -> LiveWorkout {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 2 }
        plank.plan.target = .time(seconds: 30)
        var second = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        second.plan.target = .time(seconds: 30)
        let routine = Workout(exercises: [plank, second])
        let loggedWorkout = LoggedWorkout(
            routineID: routine.id,
            routineName: "Test",
            startedAt: start,
        )
        let begun = LiveWorkout(routine: routine, loggedWorkout: loggedWorkout)
            .beginningCount(at: start)
        return LiveWorkout(routine: routine, loggedWorkout: begun)
    }

    private static func key(
        _ live: LiveWorkout,
        phase: WorkoutPhase,
        shown: LiveWorkout? = nil,
        isScrolledAway: Bool = false,
    ) -> WorkoutKey {
        WorkoutKey(
            stored: live,
            shown: shown ?? live,
            phase: phase,
            wayBack: nil,
            isScrolledAway: isScrolledAway,
        )
    }

    @Test("During Starts in the key is Start now, and its tap starts the set")
    func startsIn() throws {
        let key = try Self.key(Self.live(), phase: .timing(.startsIn))
        #expect(key.role == .startNow)
        #expect(key.tap == .startNow)
        #expect(key.countTap(by: 15) == .nothing)
        #expect(key.runOut == .nothing)
    }

    @Test("While the set counts, the key is Log early, +15 s adds, and a tap logs")
    func counting() throws {
        let live = try Self.live()
        let key = Self.key(live, phase: .timing(.counting))
        #expect(key.role == .count("Log early"))
        #expect(key.countTap(by: 15) == .extendCount(by: 15))
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        #expect(key.tap == .log(set, of: row, impact: .set, leadingTo: .nextSet))
    }

    @Test("The count's end logs with the heavy tap, scrolled away too, never mid-log")
    func runOut() throws {
        let live = try Self.live()
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        let expected = WorkoutKey.Tap.log(set, of: row, impact: .runOut, leadingTo: .nextSet)
        #expect(Self.key(live, phase: .timing(.counting)).runOut == expected)
        #expect(Self.key(live, phase: .timing(.counting), isScrolledAway: true).runOut == expected)
        #expect(Self.key(live, phase: .held(set)).runOut == .nothing)
        #expect(Self.key(live, phase: .timing(.startsIn)).runOut == .nothing)
    }

    @Test("A timed set just logged and held keeps its count, stopped, until the next shows")
    func held() throws {
        let live = try Self.live()
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        // "Starts in" ends 10 s in; logged 12 s into the set's own 30.
        let logged = LiveWorkout(
            routine: live.routine,
            loggedWorkout: live.logging(set, of: row, at: Self.start.addingTimeInterval(22)),
        )
        #expect(logged.loggedCount(of: set) == LoggedCount(length: 30, done: 12))
        let key = Self.key(logged, phase: .held(set), shown: logged.hiding([set]))
        #expect(key.drawnCount == .counting)
        #expect(key.role == .count("Log early"))
        #expect(key.countTap(by: 15) == .nothing)
        // Rolled on, the next set's "Starts in" takes over: one swap, from the count.
        let next = Self.key(logged, phase: .timing(.startsIn))
        #expect(next.drawnCount == .startsIn)
        #expect(next.role == .startNow)
    }

    @Test("On to another timed exercise the key holds the set logged until the rows shift")
    func moveToTimed() throws {
        var live = try Self.live()
        // Both sets of the first plank logged, early, the second's count running 5 s.
        for seconds in [15.0, 40.0] {
            let set = try #require(live.currentSet)
            let row = try #require(live.currentExercise)
            let at = Self.start.addingTimeInterval(seconds)
            live = LiveWorkout(
                routine: live.routine,
                loggedWorkout: live.logging(set, of: row, at: at),
            )
            live = LiveWorkout(routine: live.routine, loggedWorkout: live.startingCountNow(at: at))
            live = LiveWorkout(routine: live.routine, loggedWorkout: live.beginningCount(at: at))
        }
        let last = try #require(live.loggedWorkout.sets.last?.planned)
        var move = WorkoutPhase.Move(set: last, isBack: false, startsRound: false, beat: .shown)
        let held = Self.key(live, phase: .movingOn(move))
        #expect(held.drawnCount == .counting, "The count logged, held full for its beat")
        #expect(held.phase.loggedAndDrawn == last)
        move.beat = .shifting
        let shifting = Self.key(live, phase: .movingOn(move))
        #expect(shifting.phase.loggedAndDrawn == nil)
        #expect(shifting.drawnCount == .startsIn, "Then Start now, as the move begins")
        #expect(shifting.role == .startNow)
        #expect(shifting.tap == .nothing, "Nothing while the move plays")
    }

    @Test("Moving out of a rest the key is the count's, which the rest's end began")
    func fromRest() throws {
        let live = try Self.live()
        var move = try WorkoutPhase.Move(
            set: #require(live.currentSet),
            isBack: false,
            startsRound: false,
            beat: .shown,
        )
        move.isFromRest = true
        let key = Self.key(live, phase: .movingOn(move))
        #expect(key.drawnCount == .counting)
        #expect(key.role == .count("Log early"))
    }

    @Test("A reps set's key is Log set, as before")
    func reps() throws {
        let routine = try Workout(exercises: [WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }])
        let loggedWorkout = LoggedWorkout(
            routineID: routine.id,
            routineName: "Test",
            startedAt: Self.start,
        )
        let key = Self.key(
            LiveWorkout(routine: routine, loggedWorkout: loggedWorkout),
            phase: .running,
        )
        #expect(key.drawnCount == nil)
        #expect(key.role == .log("Log set"))
    }
}

import Foundation
import Testing
@testable import WorkoutStore

/// The key on a timed set: "Start now" during "Starts in", the log key with +15 s while it
/// counts, and the log its end makes.
@Suite("Workout key on a timed set")
struct WorkoutKeyCountTests {
    private static func live() throws -> LiveWorkout {
        var plank = try RoutineExercise.builtIn("Plank") { $0.sets = 2 }
        plank.plan.target = .time(seconds: 30)
        let routine = Routine(exercises: [plank])
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let workout = Workout(routineID: routine.id, routineName: "Test", startedAt: start)
        let begun = LiveWorkout(routine: routine, workout: workout).beginningCount(at: start)
        return LiveWorkout(routine: routine, workout: begun)
    }

    private static func key(
        _ live: LiveWorkout,
        _ stage: CountStage?,
        phase: WorkoutPhase = .running,
        isScrolledAway: Bool = false,
    ) -> WorkoutKey {
        WorkoutKey(
            stored: live,
            shown: live,
            phase: phase,
            wayBack: nil,
            isScrolledAway: isScrolledAway,
            countStage: stage,
        )
    }

    @Test("During Starts in the key is Start now, and its tap starts the set")
    func startsIn() throws {
        let key = try Self.key(Self.live(), .startsIn)
        #expect(key.role == .startNow)
        #expect(key.tap == .startNow)
        #expect(key.countTap(by: 15) == .nothing)
        #expect(key.runOut == .nothing)
    }

    @Test("While the set counts, the key is its log key, +15 s adds, and a tap logs")
    func counting() throws {
        let live = try Self.live()
        let key = Self.key(live, .counting)
        #expect(key.role == .count("Log set"))
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
        #expect(Self.key(live, .counting).runOut == expected)
        #expect(Self.key(live, .counting, isScrolledAway: true).runOut == expected)
        #expect(Self.key(live, .counting, phase: .held(set)).runOut == .nothing)
    }

    @Test("A timed set just logged and held keeps its count, stopped, until the next shows")
    func held() throws {
        let live = try Self.live()
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        // "Starts in" ends 10 s in; logged 12 s into the set's own 30.
        let logged = LiveWorkout(
            routine: live.routine,
            workout: live.logging(set, of: row, at: start.addingTimeInterval(22)),
        )
        #expect(logged.loggedCount(of: set) == LoggedCount(length: 30, done: 12))
        let key = WorkoutKey(
            stored: logged,
            shown: logged.hiding([set]),
            phase: .held(set),
            wayBack: nil,
            isScrolledAway: false,
            countStage: .startsIn,
        )
        #expect(key.drawnCount == .counting)
        #expect(key.keptCount == LoggedCount(length: 30, done: 12))
        #expect(key.role == .count("Log set"))
        #expect(key.countTap(by: 15) == .nothing)
        // Shown, the next set's "Starts in" takes over: one swap, from the count.
        let next = Self.key(logged, .startsIn)
        #expect(next.keptCount == nil)
        #expect(next.role == .startNow)
    }

    @Test("Moving out of a rest, the slot's count is the key's; moving on from a reps set, none")
    func fromRest() throws {
        let live = try Self.live()
        var move = try WorkoutPhase.Move(
            set: #require(live.currentSet),
            isBack: false,
            startsRound: false,
            beat: .shown,
        )
        #expect(Self.key(live, .counting, phase: .movingOn(move)).drawnCount == nil)
        move.isFromRest = true
        let key = Self.key(live, .counting, phase: .movingOn(move))
        #expect(key.drawnCount == .counting)
        #expect(key.role == .count("Log set"))
    }

    @Test("A reps set's key is Log set, as before")
    func reps() throws {
        let key = try Self.key(Self.live(), nil)
        #expect(key.role == .log("Log set"))
    }
}

import Foundation
import Testing
@testable import WorkoutStore

/// The key on a timed set: none during "Start in", "Log early" with +15 s while it counts, and
/// the log its end makes, all from the phase.
@Suite("Workout key on a timed set")
struct WorkoutKeyCountTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// A workout on two planks, the first of two sets, its count begun at `start` and counting
    /// from 10 on the clock.
    private static func live() throws -> LiveWorkout {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 2 }
        plank.plan.target = .time(seconds: 30)
        var second = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        second.plan.target = .time(seconds: 30)
        let workout = Workout(exercises: [plank, second])
        let loggedWorkout = LoggedWorkout(
            workoutID: workout.id,
            workoutName: "Test",
            startedAt: start,
        )
        var begun = LiveWorkout(workout: workout, loggedWorkout: loggedWorkout)
            .beginningCount(at: start)
        begun.count?.startClock = 10
        return LiveWorkout(workout: workout, loggedWorkout: begun)
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

    @Test("During Start in no key shows, and no tap starts or logs the set")
    func startIn() throws {
        let key = try Self.key(Self.live(), phase: .timing(.startIn))
        #expect(key.waitsToStart)
        #expect(key.role == .count("Log early"), "The key that comes in as the set is up")
        #expect(key.tap == .nothing)
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
        #expect(Self.key(live, phase: .timing(.startIn)).runOut == .nothing)
    }

    @Test("Paused in Start in, Continue shows and resumes; nothing starts, adds, or logs")
    func pausedStartIn() throws {
        let key = try Self.key(Self.paused(Self.live()), phase: .timing(.startIn))
        #expect(key.role == .continueWorkout)
        #expect(key.tap == .continueWorkout)
        #expect(!key.waitsToStart, "Continue shows, though no key shows while it runs")
        #expect(key.pauseMovesKey, "A resume takes the key away again")
        #expect(key.countTap(by: 15) == .nothing)
        #expect(key.runOut == .nothing)
    }

    @Test("Paused mid-count, Continue in Log early's place; +15 s and the count's end do nothing")
    func pausedCounting() throws {
        let key = try Self.key(Self.paused(Self.live()), phase: .timing(.counting))
        #expect(key.role == .continueWorkout)
        #expect(key.tap == .continueWorkout)
        #expect(!key.pauseMovesKey, "The key only changes kind")
        #expect(key.countTap(by: 15) == .nothing)
        #expect(key.runOut == .nothing)
    }

    /// `live` paused a minute after `start`.
    private static func paused(_ live: LiveWorkout) -> LiveWorkout {
        var paused = live
        paused.loggedWorkout = live.loggedWorkout.pausing(at: start.addingTimeInterval(60))
        return paused
    }

    @Test("A timed set just logged and held keeps its count, stopped, until the next shows")
    func held() throws {
        let live = try Self.live()
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        // "Start in" ends 10 s in; logged 12 s into the set's own 30.
        let logged = LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.logging(set, of: row, at: Self.start.addingTimeInterval(22)),
        )
        #expect(logged.loggedCount(of: set) == LoggedCount(length: 30, done: 12))
        let key = Self.key(logged, phase: .held(set), shown: logged.hiding([set]))
        #expect(key.drawnCount == .counting)
        #expect(key.role == .count("Log early"))
        #expect(key.countTap(by: 15) == .nothing)
        #expect(!key.waitsToStart, "The set just logged keeps its key until the next shows")
        // Rolled on, the next set's "Start in" takes over, with no key.
        let next = Self.key(logged, phase: .timing(.startIn))
        #expect(next.drawnCount == .startIn)
        #expect(next.waitsToStart)
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
                workout: live.workout,
                loggedWorkout: live.logging(set, of: row, at: at),
            )
            live = LiveWorkout(workout: live.workout, loggedWorkout: live.beginningCount(at: at))
        }
        let last = try #require(live.loggedWorkout.sets.last?.planned)
        var move = WorkoutPhase.Move(set: last, isBack: false, startsRound: false, beat: .shown)
        let held = Self.key(live, phase: .movingOn(move))
        #expect(held.drawnCount == .counting, "The count logged, held full for its beat")
        #expect(held.phase.loggedAndDrawn == last)
        move.beat = .shifting
        let shifting = Self.key(live, phase: .movingOn(move))
        #expect(shifting.phase.loggedAndDrawn == nil)
        #expect(shifting.drawnCount == .startIn, "Then Start in, as the move begins")
        #expect(shifting.tap == .nothing, "Nothing while the move plays")
        // Landed, the next set's "Start in" has no key.
        let landed = Self.key(live, phase: .timing(.startIn))
        #expect(landed.waitsToStart)
    }

    /// The reps set's key is Log set, and stays it once the rows shift, though the timed set
    /// shown below waits on its "Start in": read from that set, it turned to a full "Log early"
    /// with +15 s for a few frames before the roll took it away.
    @Test("On from a reps set to a timed one the key stays Log set until it leaves")
    func moveFromRepsToTimed() throws {
        try Self.expectHeldKey(.log("Log set"), timedFirst: false)
    }

    /// The mirror: the timed set's key stays its own, full, rather than turning to the reps
    /// set's log key at the shift and leaving at the roll for its "Start in".
    @Test("On from a timed set to a reps one the key stays Log early until it leaves")
    func moveFromTimedToReps() throws {
        try Self.expectHeldKey(.count("Log early"), timedFirst: true)
    }

    /// On a workout of a plank and push-ups, `timedFirst` or not, with the first exercise's one
    /// set logged: through the move on to the second, the key stays `role` until the roll,
    /// which takes it away for the second set's "Start in".
    private static func expectHeldKey(_ role: WorkoutKey.Role, timedFirst: Bool) throws {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        plank.plan.target = .time(seconds: 30)
        let pushUp = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        let workout = Workout(exercises: timedFirst ? [plank, pushUp] : [pushUp, plank])
        var begun = LiveWorkout(
            workout: workout,
            loggedWorkout: LoggedWorkout(
                workoutID: workout.id,
                workoutName: "Test",
                startedAt: start,
            ),
        )
        if timedFirst {
            begun = LiveWorkout(workout: workout, loggedWorkout: begun.beginningCount(at: start))
        }
        let live = try TimedSetTests.logged(begun, at: 20)
        let set = try #require(live.loggedWorkout.sets.last?.planned)
        #expect(live.isOnTimedSet != timedFirst)
        var move = WorkoutPhase.Move(set: set, isBack: false, startsRound: false, beat: .shown)
        for beat in [WorkoutPhase.Move.Beat.shown, .landed, .shifting] {
            move.beat = beat
            let key = Self.key(live, phase: .movingOn(move))
            #expect(key.role == role, "At \(beat)")
            #expect(!key.waitsToStart, "At \(beat)")
        }
        move.beat = .rolled
        #expect(Self.key(live, phase: .movingOn(move)).waitsToStart, "Rolled, no key")
    }

    @Test("Moving out of a rest onto the same exercise the key is the count's, the rest's end's")
    func fromRest() throws {
        var live = try Self.live()
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        live = LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.logging(set, of: row, at: Self.start.addingTimeInterval(40)),
        )
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

    /// After End's choice the store holds no workout in progress, and the screen draws the one
    /// End found until it goes, its key as it was: read from the phase's timing alone, the count's
    /// keys turned to Log set under a finish's "++", and a "Start in" brought its key in.
    @Test("Ended mid-count or mid-Start in, the key stays as End found it until the workout goes")
    func endedMidCount() throws {
        let live = try Self.live()
        for stage in [CountStage.counting, .startIn] {
            let key = try Self.ended(live, on: stage)
            #expect(key.drawnCount == stage)
            #expect(key.role == .count("Log early"))
            #expect(key.waitsToStart == (stage == .startIn), "Its key came in or went")
        }
    }

    @Test("Ended mid-Start in on a reps set, its key stays away until the workout goes")
    func endedMidRepsStartIn() throws {
        let workout = try Workout(exercises: [WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }])
        let loggedWorkout = LoggedWorkout(
            workoutID: workout.id,
            workoutName: "Test",
            startedAt: Self.start,
        )
        let key = try Self.ended(
            LiveWorkout(workout: workout, loggedWorkout: loggedWorkout),
            on: .startIn,
        )
        #expect(key.role == .log("Log set"))
        #expect(key.waitsToStart, "The log key came in under the finish's \"++\"")
    }

    /// The key End leaves on `live` at rest on `stage`, with the store holding no workout.
    private static func ended(_ live: LiveWorkout, on stage: CountStage) throws -> WorkoutKey {
        var phase = WorkoutPhase.timing(stage)
        let ended = phase.end(live.loggedWorkout, at: start.addingTimeInterval(15))
        try #require(ended, "End did not take the workout at rest on its count")
        return WorkoutKey(
            stored: nil,
            shown: live,
            phase: phase,
            wayBack: nil,
            isScrolledAway: false,
        )
    }

    @Test("A reps set's key is Log set, and logs, once its Start in is over; none through it")
    func reps() throws {
        let workout = try Workout(exercises: [WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }])
        let loggedWorkout = LoggedWorkout(
            workoutID: workout.id,
            workoutName: "Test",
            startedAt: Self.start,
        )
        let live = LiveWorkout(workout: workout, loggedWorkout: loggedWorkout)
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        let running = Self.key(live, phase: .running)
        #expect(running.drawnCount == nil)
        #expect(running.role == .log("Log set"))
        #expect(!running.waitsToStart)
        #expect(running.tap == .log(set, of: row, impact: .set, leadingTo: .nextSet))
        let startIn = Self.key(live, phase: .timing(.startIn))
        #expect(startIn.waitsToStart)
        #expect(startIn.tap == .nothing)
    }
}

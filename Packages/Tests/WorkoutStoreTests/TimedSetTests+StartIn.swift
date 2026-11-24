import Foundation
import Testing
@testable import WorkoutStore

extension TimedSetTests {
    @Test("A reps set's Start in counts; it logs during it, and the next set begins none")
    func reps() throws {
        let workout = try Workout(exercises: [WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }])
        let live = Self.begun(workout)
        let lead = Double(LiveWorkout.startIn)
        #expect(live.loggedWorkout.count?.startClock == lead)
        #expect(live.countStage(at: Self.at(lead - 1)) == .startIn)
        #expect(live.countStage(at: Self.at(lead)) == nil, "Over, the set stands")
        let after = try Self.logged(live, at: lead - 1)
        let first = after.loggedWorkout.sets.first
        #expect(first?.target == first?.plannedTarget)
        #expect(after.loggedWorkout.count == nil)
        #expect(Self.landed(after, at: 6).loggedWorkout.count == nil)
    }

    @Test("Start in comes as each exercise does, 5 s before a set's other side, none between sets")
    func startInBefore() throws {
        let squat = try WorkoutExercise.builtIn("Bulgarian split squat") { $0.sets = 2 }
        let bench = try WorkoutExercise.builtIn("Dumbbell bench press") { $0.sets = 2 }
        let goblet = try WorkoutExercise.builtIn("Goblet squat") { $0.sets = 2 }
        var workout = Workout(exercises: [squat, bench, goblet])
        workout.join(workout.exercises[1].id, .below)
        let leads = workout.setOrder.map { workout.startIn(before: $0) }
        let first = LiveWorkout.startIn
        let side = LiveWorkout.startInSides
        // Left, right, left, right; then the superset's members alternating, two rounds.
        #expect(leads == [first, side, 0, side, first, first, first, first], "\(leads)")
    }

    @Test("The workout's time starts as the first Start in ends, or at a log or Start now before")
    func timeStartsWithFirstSet() throws {
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
        let workout = Workout(exercises: [push])
        let made = LoggedWorkout(workoutID: workout.id, workoutName: "Test", startedAt: Self.at(0))
        let lead = Double(LiveWorkout.startIn)
        let landed = LiveWorkout(workout: workout, loggedWorkout: made)
            .landingStart(at: Self.at(0.5))
        // "Start in" counts up to zero, where the set and the time begin.
        #expect(landed.clock(at: Self.at(0.5)) == -lead)
        #expect(landed.count?.startClock == 0)
        #expect(landed.elapsed(at: Self.at(3)) == .zero)
        #expect(landed.elapsed(at: Self.at(0.5 + lead + 1)) == .seconds(1))

        // Logged 2 s into "Start in": the time starts at the log, and the rest with it.
        let live = LiveWorkout(workout: workout, loggedWorkout: landed)
        let logged = try Self.logged(live, at: 2.5)
        #expect(logged.loggedWorkout.startedAt == Self.at(2.5))
        #expect(logged.loggedWorkout.sets.first?.clockWhenLogged == 0)

        // "Start now" on a timed first set: the time and the set's count start at the tap.
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        plank.plan.target = .time(seconds: 30)
        let timed = Workout(exercises: [plank])
        let waiting = LiveWorkout(workout: timed, loggedWorkout: made)
            .landingStart(at: Self.at(0.5))
        let now = LiveWorkout(workout: timed, loggedWorkout: waiting)
            .startingCountNow(at: Self.at(2.5))
        #expect(now.startedAt == Self.at(2.5))
        #expect(now.count?.startClock == 0)

        // Under way, a landing only begins a count: the clock is never set back.
        #expect(logged.landingStart(at: Self.at(30)).startedAt == Self.at(2.5))
        var resumed = made
        resumed.pausedSeconds = 3
        var paused = made
        paused.pausedAt = Self.at(0.2)
        for kept in [resumed, paused] {
            let live = LiveWorkout(workout: workout, loggedWorkout: kept)
            #expect(live.landingStart(at: Self.at(10)).startedAt == Self.at(0))
        }
        // A landing that waited, as on the phone being unlocked, loses none of the time.
        let late = LiveWorkout(workout: workout, loggedWorkout: made).landingStart(at: Self.at(180))
        #expect(late.startedAt == Self.at(0))
        #expect(late.count?.startClock == 180 + Double(LiveWorkout.startIn))
    }

    @Test("After a rest onto another exercise, Start in runs from the rest's end")
    func startInAfterRest() throws {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        plank.plan.target = .time(seconds: 30)
        plank.setRest(20)
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        let live = Self.started(Workout(exercises: [plank, push]))
        // Counts 10 to 40, then rests 40 to 60.
        let after = try Self.logged(live, at: 40)
        #expect(after.beginningCount(at: Self.at(50)).count == nil, "Not while the rest runs")
        let begun = Self.landed(after, at: 60.5)
        #expect(begun.loggedWorkout.count?.startClock == 60 + Double(LiveWorkout.startIn))
        #expect(begun.countStage(at: Self.at(61)) == .startIn)
    }
}

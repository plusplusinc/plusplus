import Foundation
import Testing
@testable import WorkoutStore

extension TimedSetTests {
    @Test("A reps set's Start in counts through its hold; logged, the next set begins none")
    func reps() throws {
        let workout = try Workout(exercises: [WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }])
        let live = Self.begun(workout)
        let lead = Self.lead
        #expect(live.loggedWorkout.count?.startClock == lead)
        #expect(live.countStage(at: Self.at(lead - LiveWorkout.startInHold)) == .startIn)
        #expect(live.countStage(at: Self.at(lead)) == nil, "Over, the set stands")
        let after = try Self.logged(live, at: lead + 1)
        let first = after.loggedWorkout.sets.first
        #expect(first?.target == first?.plannedTarget)
        #expect(after.loggedWorkout.count == nil)
        #expect(Self.landed(after, at: lead + 2).loggedWorkout.count == nil)
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

    @Test("The workout's time starts as the first Start in's hold ends, or at a log before")
    func timeStartsWithFirstSet() throws {
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
        let workout = Workout(exercises: [push])
        let made = WorkoutSession(workoutID: workout.id, workoutName: "Test", startedAt: Self.at(0))
        let lead = Self.lead
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

        // Skip rest a moment after a log: the rest keeps its length, and holds what it had left.
        let skipped = LiveWorkout(
            workout: workout,
            loggedWorkout: logged.loggedWorkout.logging(
                PlannedSet(row: push.id, round: 9),
                of: push,
                at: Self.at(13.1),
            ),
        )
        let over = LiveWorkout(
            workout: workout,
            loggedWorkout: skipped.skippingRest(at: Self.at(13.3)),
        )
        let tap = over.loggedWorkout.clock(at: Self.at(13.3))
        let rest = try #require(over.rest())
        #expect(rest.length == skipped.rest()?.length)
        #expect(rest.skippedAt == tap)
        #expect(rest.shownLeft(atClock: tap + 5) == rest.remaining(atClock: tap))

        // A device clock set back under way never reads as a time not started.
        #expect(logged.loggedWorkout.clock(at: Self.at(-100)) == 0)

        // Under way, a landing only begins a count: the clock is never set back.
        #expect(logged.landingStart(at: Self.at(30)).startedAt == Self.at(2.5))
        let resumed = WorkoutSession(
            workoutID: workout.id,
            workoutName: "Test",
            startedAt: Self.at(0),
            pausedSeconds: 3,
        )
        var paused = made
        paused.pausedAt = Self.at(0.2)
        for kept in [resumed, paused] {
            let live = LiveWorkout(workout: workout, loggedWorkout: kept)
            #expect(live.landingStart(at: Self.at(10)).startedAt == Self.at(0))
        }
        // A landing that waited, as on the phone being unlocked, loses none of the time.
        let late = LiveWorkout(workout: workout, loggedWorkout: made).landingStart(at: Self.at(180))
        #expect(late.startedAt == Self.at(0))
        #expect(late.count?.startClock == 180 + lead)
    }

    @Test("Reopened in Start in or its 0:00 hold, the screen opens on it where the clock says")
    func reopenedInStartIn() throws {
        let plank = try Self.begun(Self.workout())
        let push = try Self.begun(Workout(exercises: [
            WorkoutExercise.builtIn("Push-up") { $0.sets = 1 },
        ]))
        let hold = Self.lead - LiveWorkout.startInHold / 2
        for (live, up) in [(plank, WorkoutPhase.timing(.counting)), (push, .running)] {
            for second in [2, hold] {
                #expect(WorkoutPhase(resuming: live, at: Self.at(second)) == .timing(.startIn))
                // Its count is kept, not begun again from the relaunch.
                #expect(live.beginningCount(at: Self.at(second)) == live.loggedWorkout)
            }
            #expect(WorkoutPhase(resuming: live, at: Self.at(Self.lead)) == up)
        }
        #expect(plank.timedSet?.startIn(atClock: 2) == Self.lead - 2)
    }

    @Test("After a rest onto another exercise, Start in runs from where the rest moved on")
    func startInAfterRest() throws {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        plank.plan.target = .time(seconds: 30)
        plank.setRest(20)
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        let live = Self.started(Workout(exercises: [plank, push]))
        // Counts 10 to 40, then rests 40 to 60, holding 0:00 a moment.
        let after = try Self.logged(live, at: 40)
        #expect(after.beginningCount(at: Self.at(50)).count == nil, "Not while the rest runs")
        #expect(after.beginningCount(at: Self.at(60.5)).count == nil, "Nor while it holds 0:00")
        let leave = 60 + LiveWorkout.restHold
        let begun = Self.landed(after, at: leave + 0.5)
        #expect(begun.loggedWorkout.count?.startClock == leave + Self.lead)
        #expect(begun.countStage(at: Self.at(leave + 1)) == .startIn)
    }
}

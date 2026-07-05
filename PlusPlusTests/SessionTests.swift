import Foundation
import Testing
import SwiftData
@testable import PlusPlus

@Suite("WorkoutSession")
struct SessionTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self,
            WorkoutExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Superset (Y Raise + T Raise) × 3 sets, then Band Pulses × 2 sets.
    private func makePTWorkout(context: ModelContext) -> Workout {
        let workout = Workout(name: "Shoulder PT")
        context.insert(workout)

        let yRaise = Exercise(name: "Y Raise", muscleGroup: .shoulders)
        let tRaise = Exercise(name: "T Raise", muscleGroup: .shoulders)
        let pulses = Exercise(name: "Band Pulses", muscleGroup: .shoulders)
        context.insert(yRaise)
        context.insert(tRaise)
        context.insert(pulses)

        let superset = workout.addExerciseInNewGroup(yRaise, context: context)
        superset.sets = 3
        workout.addExercise(tRaise, to: superset, context: context)
        superset.sortedExercises[0].weight = 5
        superset.sortedExercises[0].reps = 10
        superset.sortedExercises[1].weight = 5
        superset.sortedExercises[1].reps = 10

        let pulsesGroup = workout.addExerciseInNewGroup(pulses, context: context)
        pulsesGroup.sets = 2
        pulsesGroup.sortedExercises[0].reps = 15
        pulsesGroup.sortedExercises[0].repsUpper = 20

        return workout
    }

    @Test("Supersets rotate: A B A B A B, then the next group")
    func rotationOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = makePTWorkout(context: context)

        let session = WorkoutSession.start(from: workout, context: context)
        let logs = session.sortedSetLogs

        #expect(logs.count == 8)
        #expect(logs.map(\.exerciseName) == [
            "Y Raise", "T Raise", "Y Raise", "T Raise", "Y Raise", "T Raise",
            "Band Pulses", "Band Pulses",
        ])
        #expect(logs.map(\.setNumber) == [1, 1, 2, 2, 3, 3, 1, 2])
        #expect(logs.map(\.groupIndex) == [0, 0, 0, 0, 0, 0, 1, 1])
        #expect(logs.map(\.order) == Array(0..<8))
    }

    @Test("Targets are copied from the plan, including rep ranges")
    func targetsCopied() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = makePTWorkout(context: context)

        let session = WorkoutSession.start(from: workout, context: context)
        let logs = session.sortedSetLogs

        #expect(logs[0].targetWeight == 5)
        #expect(logs[0].targetRepsLower == 10)
        #expect(logs[0].targetRepsUpper == nil)

        let pulsesLog = logs[6]
        #expect(pulsesLog.targetWeight == nil)
        #expect(pulsesLog.targetRepsLower == 15)
        #expect(pulsesLog.targetRepsUpper == 20)
        #expect(pulsesLog.targetReps.display == "15–20")
    }

    @Test("Session snapshots survive template edits")
    func snapshotsSurviveTemplateEdits() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = makePTWorkout(context: context)

        let session = WorkoutSession.start(from: workout, context: context)

        workout.name = "Renamed"
        let firstGroup = workout.sortedGroups[0]
        context.delete(firstGroup)
        workout.reindexGroups()

        #expect(session.workoutName == "Shoulder PT")
        #expect(session.sortedSetLogs.count == 8)
        #expect(session.sortedSetLogs[0].exerciseName == "Y Raise")
    }

    @Test("nextPendingLog walks through the session as sets complete")
    func pendingLogAdvances() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = makePTWorkout(context: context)

        let session = WorkoutSession.start(from: workout, context: context)

        #expect(session.nextPendingLog === session.sortedSetLogs[0])

        session.sortedSetLogs[0].actualReps = 10
        session.sortedSetLogs[0].actualWeight = 5
        session.sortedSetLogs[0].completedAt = Date()

        #expect(session.nextPendingLog === session.sortedSetLogs[1])
        #expect(session.completedSetLogs.count == 1)

        for log in session.sortedSetLogs {
            log.completedAt = Date()
        }
        #expect(session.nextPendingLog == nil)
    }

    @Test("Finishing stamps endedAt and duration")
    func finishing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = makePTWorkout(context: context)

        let start = Date(timeIntervalSince1970: 1_000_000)
        let session = WorkoutSession.start(from: workout, context: context, at: start)
        #expect(!session.isFinished)
        #expect(session.duration == nil)

        session.finish(at: start.addingTimeInterval(1800))
        #expect(session.isFinished)
        #expect(session.duration == 1800)
    }

    @Test("Duration exercises carry their target through")
    func durationTargets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workout = Workout(name: "Core")
        context.insert(workout)
        let plank = Exercise(name: "Plank", muscleGroup: .core, exerciseType: .duration)
        context.insert(plank)
        let group = workout.addExerciseInNewGroup(plank, context: context)
        group.sets = 2
        group.sortedExercises[0].durationSeconds = 60

        let session = WorkoutSession.start(from: workout, context: context)
        let logs = session.sortedSetLogs

        #expect(logs.count == 2)
        #expect(logs[0].exerciseType == .duration)
        #expect(logs[0].targetDuration == 60)
        #expect(logs[0].targetWeight == nil)
    }
}

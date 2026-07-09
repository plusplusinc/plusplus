import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("WorkoutSession")
struct SessionTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Superset (Y Raise + T Raise) × 3 sets, then Band Pulses × 2 sets.
    private func makePTRoutine(context: ModelContext) -> Routine {
        let routine = Routine(name: "Shoulder PT")
        context.insert(routine)

        let yRaise = Exercise(name: "Y Raise", muscleGroup: .shoulders)
        let tRaise = Exercise(name: "T Raise", muscleGroup: .shoulders)
        let pulses = Exercise(name: "Band Pulses", muscleGroup: .shoulders)
        context.insert(yRaise)
        context.insert(tRaise)
        context.insert(pulses)

        let superset = routine.addExerciseInNewGroup(yRaise, context: context)
        superset.sets = 3
        routine.addExercise(tRaise, to: superset, context: context)
        superset.sortedExercises[0].weight = 5
        superset.sortedExercises[0].reps = 10
        superset.sortedExercises[1].weight = 5
        superset.sortedExercises[1].reps = 10

        let pulsesGroup = routine.addExerciseInNewGroup(pulses, context: context)
        pulsesGroup.sets = 2
        pulsesGroup.sortedExercises[0].reps = 15
        pulsesGroup.sortedExercises[0].repsUpper = 20

        return routine
    }

    @Test("Supersets rotate: A B A B A B, then the next group")
    func rotationOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = makePTRoutine(context: context)

        let session = WorkoutSession.start(from: routine, context: context)
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
        let routine = makePTRoutine(context: context)

        let session = WorkoutSession.start(from: routine, context: context)
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
        let routine = makePTRoutine(context: context)

        let session = WorkoutSession.start(from: routine, context: context)

        routine.name = "Renamed"
        let firstGroup = routine.sortedGroups[0]
        context.delete(firstGroup)
        routine.reindexGroups()

        #expect(session.routineName == "Shoulder PT")
        #expect(session.sortedSetLogs.count == 8)
        #expect(session.sortedSetLogs[0].exerciseName == "Y Raise")
    }

    @Test("nextPendingLog walks through the session as sets complete")
    func pendingLogAdvances() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = makePTRoutine(context: context)

        let session = WorkoutSession.start(from: routine, context: context)

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

    @Test("Session snapshots the routine's rest setting")
    func restSnapshot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = makePTRoutine(context: context)
        routine.restSeconds = 45

        let session = WorkoutSession.start(from: routine, context: context)
        #expect(session.restSeconds == 45)

        routine.restSeconds = 120
        #expect(session.restSeconds == 45, "Later template edits must not change the running session")
    }

    @Test("Finishing stamps endedAt and duration")
    func finishing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = makePTRoutine(context: context)

        let start = Date(timeIntervalSince1970: 1_000_000)
        let session = WorkoutSession.start(from: routine, context: context, at: start)
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

        let routine = Routine(name: "Core")
        context.insert(routine)
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        context.insert(plank)
        let group = routine.addExerciseInNewGroup(plank, context: context)
        group.sets = 2
        group.sortedExercises[0].durationSeconds = 60

        let session = WorkoutSession.start(from: routine, context: context)
        let logs = session.sortedSetLogs

        #expect(logs.count == 2)
        #expect(logs[0].exerciseType == .duration)
        #expect(logs[0].targetDuration == 60)
        #expect(logs[0].targetWeight == nil)
    }

    // MARK: - Ad-hoc sessions (#239)

    @Test("Appending builds pending solo blocks from exercise defaults")
    func appendExerciseAddsPendingSoloBlocks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let session = WorkoutSession.startEmpty(context: context)
        #expect(session.routine == nil)
        #expect(session.routineName == WorkoutSession.scratchName)
        #expect(session.currentLog == nil)

        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)
        context.insert(curl)
        curl.defaultWeight = 25
        curl.defaultReps = 8
        let plank = Exercise(name: "Probe Plank", muscleGroup: .core, exerciseType: .duration)
        context.insert(plank)

        let curls = session.appendExercise(curl, context: context)
        #expect(curls.count == 3)
        #expect(curls.map(\.setNumber) == [1, 2, 3])
        let allInFirstGroup = curls.allSatisfy { $0.groupIndex == 0 }
        #expect(allInFirstGroup)
        #expect(curls.first?.targetWeight == 25)
        #expect(curls.first?.targetRepsLower == 8)

        let planks = session.appendExercise(plank, sets: 2, context: context)
        #expect(planks.count == 2)
        #expect(planks.first?.groupIndex == 1)
        #expect(planks.first?.targetDuration == 45)
        #expect(session.sortedSetLogs.map(\.order) == [0, 1, 2, 3, 4])
        #expect(session.currentLog?.exerciseName == "Probe Curl")
    }

    @Test("Save as routine materializes what was performed")
    func saveAsRoutineMaterializesPerformedWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Forces the unique-name suffix path for the blank-name default.
        context.insert(Routine(name: "Scratch workout"))

        let session = WorkoutSession.startEmpty(context: context)
        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        context.insert(press)
        let logs = session.appendExercise(press, sets: 3, context: context)

        // Two sets done (the second with an edited weight); the third
        // abandoned — the routine records what happened, not the plan.
        logs[0].actualWeight = 95
        logs[0].actualReps = 10
        session.complete(logs[0])
        logs[1].actualWeight = 100
        logs[1].actualReps = 8
        session.complete(logs[1])
        session.finish()

        let routines = try context.fetch(FetchDescriptor<Routine>())
        let routine = try #require(session.saveAsRoutine(named: "  ", among: routines, context: context))

        #expect(routine.name == "Scratch workout 2")
        #expect(routine.sortedGroups.count == 1)
        let group = try #require(routine.sortedGroups.first)
        #expect(group.sets == 2)
        let entry = try #require(group.sortedExercises.first)
        #expect(entry.exercise === press)
        #expect(entry.weight == 100)
        #expect(entry.reps == 8)
        #expect(entry.repsUpper == nil)
        #expect(press.inLibrary, "referenced exercises join the library")
        #expect(session.routine === routine)
        #expect(session.routineName == "Scratch workout 2")
    }

    @Test("Save as routine needs completed work")
    func saveAsRoutineRequiresCompletedWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let session = WorkoutSession.startEmpty(context: context)
        let row = Exercise(name: "Probe Row", muscleGroup: .back)
        context.insert(row)
        session.appendExercise(row, context: context)

        #expect(session.saveAsRoutine(named: "Nope", among: [], context: context) == nil)
        let routineCount = try context.fetchCount(FetchDescriptor<Routine>())
        #expect(routineCount == 0)
    }
}

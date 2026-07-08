import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// Per-exercise default targets (#187): prefill at routine-add time,
/// auto-bump from routine edits, and interchange round-trip.
@Suite("Default targets")
struct DefaultTargetsTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("default-targets-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func addPrefillsFromExerciseDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        press.defaultWeight = 135
        press.defaultReps = 5
        context.insert(press)

        let routine = Routine(name: "Push Day")
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(press, context: context)

        let entry = try #require(group.sortedExercises.first)
        #expect(entry.weight == 135)
        #expect(entry.reps == 5)
        #expect(entry.repsUpper == nil)
    }

    @Test func addFallsBackToGlobalDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        context.insert(press)
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        context.insert(plank)

        let routine = Routine(name: "Mixed")
        context.insert(routine)
        let pressEntry = try #require(routine.addExerciseInNewGroup(press, context: context).sortedExercises.first)
        let plankEntry = try #require(routine.addExerciseInNewGroup(plank, context: context).sortedExercises.first)

        #expect(pressEntry.weight == nil)
        #expect(pressEntry.reps == 10)
        #expect(plankEntry.durationSeconds == 45)
    }

    @Test func addPrefillsDurationDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        plank.defaultDurationSeconds = 90
        context.insert(plank)

        let routine = Routine(name: "Core")
        context.insert(routine)
        let entry = try #require(routine.addExerciseInNewGroup(plank, context: context).sortedExercises.first)
        #expect(entry.durationSeconds == 90)
    }

    @Test func routineEditBumpsExerciseDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        press.defaultWeight = 135
        press.defaultReps = 5
        context.insert(press)

        let routine = Routine(name: "Push Day")
        context.insert(routine)
        let entry = try #require(routine.addExerciseInNewGroup(press, context: context).sortedExercises.first)

        entry.weight = 145
        entry.reps = 8
        entry.repsUpper = 10
        entry.bumpExerciseDefaults()

        #expect(press.defaultWeight == 145)
        #expect(press.defaultReps == 8)
        #expect(press.defaultRepsUpper == 10)

        // The duration path leaves rep-family defaults alone.
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        context.insert(plank)
        let plankEntry = try #require(routine.addExerciseInNewGroup(plank, context: context).sortedExercises.first)
        plankEntry.durationSeconds = 120
        plankEntry.bumpExerciseDefaults()
        #expect(plank.defaultDurationSeconds == 120)
        #expect(plank.defaultWeight == nil)
    }

    @Test func draftApplyClearsMismatchedFamily() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        press.defaultWeight = 135
        press.defaultReps = 5
        context.insert(press)

        let draft = ExerciseDraft(from: press)
        #expect(draft.defaultWeight == 135)
        draft.exerciseType = .duration
        draft.defaultDurationSeconds = 60
        draft.apply(to: press)

        #expect(press.defaultWeight == nil)
        #expect(press.defaultReps == nil)
        #expect(press.defaultDurationSeconds == 60)
    }

    @Test func defaultsSurviveExportImport() throws {
        let source = try makeContainer()
        let sourceContext = ModelContext(source)

        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        press.defaultWeight = 135
        press.defaultReps = 5
        press.defaultRepsUpper = 8
        sourceContext.insert(press)
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        plank.defaultDurationSeconds = 90
        sourceContext.insert(plank)

        let bundle = try InterchangeMapping.exportBundle(context: sourceContext)
        let data = try InterchangeCodec.encode(bundle)

        let target = try makeContainer()
        let targetContext = ModelContext(target)
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: data)
        try InterchangeMapping.importBundle(decoded, context: targetContext)

        let imported = try targetContext.fetch(FetchDescriptor<Exercise>())
        let byName = Dictionary(uniqueKeysWithValues: imported.map { ($0.name, $0) })
        #expect(byName["Probe Press"]?.defaultWeight == 135)
        #expect(byName["Probe Press"]?.defaultReps == 5)
        #expect(byName["Probe Press"]?.defaultRepsUpper == 8)
        #expect(byName["Probe Hold"]?.defaultDurationSeconds == 90)
    }
}

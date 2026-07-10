import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// Heart-rate target plumbing through the models: the typed accessors
/// over the JSON blobs, the #187 default bump, and the session
/// factory's snapshot rule.
@Suite("Heart rate targets")
struct HeartRateTargetTests {
    // On-disk throwaway store per container — in-memory configurations
    // share state across containers in one process (see CLAUDE.md).
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self, WorkoutSession.self, SetLog.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hrtests-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func typedAccessorRoundTrips() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Probe Bike", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(exercise)
        let entry = RoutineExercise(exercise: exercise)
        context.insert(entry)

        entry.heartRateTarget = .zone(.zone2)
        #expect(entry.heartRateTarget == .zone(.zone2))
        entry.heartRateTarget = .range(lowerBPM: 130, upperBPM: 150)
        #expect(entry.heartRateTarget == .range(lowerBPM: 130, upperBPM: 150))
        entry.heartRateTarget = nil
        #expect(entry.heartRateTargetData == nil)
    }

    @Test func bumpCopiesHeartRateDefaultForDuration() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Probe Row Machine", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(exercise)
        let entry = RoutineExercise(exercise: exercise)
        context.insert(entry)

        entry.heartRateTarget = .zone(.zone3)
        entry.bumpExerciseDefaults()
        #expect(exercise.defaultHeartRateTargetData == entry.heartRateTargetData)

        // Clearing the prescription clears the default too — the
        // default mirrors the last-edited entry, including nil.
        entry.heartRateTarget = nil
        entry.bumpExerciseDefaults()
        #expect(exercise.defaultHeartRateTargetData == nil)
    }

    @Test func freshEntryPrefillsFromDefault() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Probe Sled", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(exercise)
        exercise.defaultHeartRateTargetData = try JSONEncoder().encode(HeartRateTarget.zone(.zone4))

        let routine = Routine(name: "Probe Cardio")
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(exercise, context: context)
        #expect(group.sortedExercises.first?.heartRateTarget == .zone(.zone4))
    }

    @Test func sessionFactorySnapshotsTarget() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Probe Assault Bike", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(exercise)
        let routine = Routine(name: "Probe Intervals")
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(exercise, context: context)
        guard let entry = group.sortedExercises.first else {
            Issue.record("entry missing")
            return
        }
        entry.heartRateTarget = .zone(.zone5)

        let session = WorkoutSession.start(from: routine, context: context)
        let logs = session.sortedSetLogs
        #expect(!logs.isEmpty)
        #expect(logs.allSatisfy { $0.targetHeartRate == .zone(.zone5) })

        // The snapshot survives the template's later edits — history is
        // a record, not a reference.
        entry.heartRateTarget = nil
        let stillTargeted = logs.allSatisfy { $0.targetHeartRate == .zone(.zone5) }
        #expect(stillTargeted)
    }

    @Test func scratchAppendPrefillsFromDefault() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Probe Ski Erg", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(exercise)
        exercise.defaultHeartRateTargetData = try JSONEncoder().encode(HeartRateTarget.range(lowerBPM: 120, upperBPM: 140))

        let session = WorkoutSession.startEmpty(context: context)
        let appended = session.appendExercise(exercise, sets: 2, context: context)
        #expect(appended.count == 2)
        let allPrefilled = appended.allSatisfy { $0.targetHeartRate == .range(lowerBPM: 120, upperBPM: 140) }
        #expect(allPrefilled)
    }
}

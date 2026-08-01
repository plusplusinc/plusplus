import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// DUPE has to copy what the entry PRESCRIBES, all of it (#508, b19).
///
/// The bug these pin: `duplicateExercise` spelled its field list out by hand
/// and copied weight/reps/repsUpper/duration/heart rate while silently
/// dropping `extraTargetsData` and the group's `restSecondsOverride` — so
/// duplicating a configured cardio block lost its distance, pace and
/// resistance, plus whatever custom rest it ran. It contradicted the
/// function's own "with its targets" doc comment, and nothing caught it
/// because the function was private to a `View`.
@Suite("Routine.duplicateExercise")
struct RoutineDuplicateTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routinedupe-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A routine holding one configured cardio entry in its own group.
    private func makeWorld(context: ModelContext) throws -> (routine: Routine, group: ExerciseGroup, entry: RoutineExercise) {
        let row = Exercise(name: "Probe Row", muscleGroup: .back, isBuiltIn: true)
        context.insert(row)
        let routine = Routine(name: "Probe Cardio Day", order: 0)
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(row, context: context)
        let entry = try #require(group.sortedExercises.first)
        try context.save()
        return (routine, group, entry)
    }

    @Test("A duped entry carries the whole prescription, bag included")
    func dupeCopiesEveryTarget() throws {
        let context = ModelContext(try makeContainer())
        let world = try makeWorld(context: context)

        // The columns the old code DID copy…
        world.entry.weight = 42
        world.entry.reps = 12
        world.entry.repsUpper = 15
        world.entry.durationSeconds = 900
        world.entry.heartRateTarget = .range(lowerBPM: 130, upperBPM: 150)
        // …and the bag it dropped. This is the whole bug.
        world.entry.extraTargets = [.distance: 5000, .resistance: 6]
        try context.save()

        let copy = try #require(
            world.routine.duplicateExercise(world.entry, in: world.group, context: context)
        )

        #expect(copy.weight == 42)
        #expect(copy.reps == 12)
        #expect(copy.repsUpper == 15)
        #expect(copy.durationSeconds == 900)
        #expect(copy.heartRateTarget == world.entry.heartRateTarget)
        // The triad: distance and resistance must survive the copy.
        #expect(copy.extraTargets[.distance] == 5000)
        #expect(copy.extraTargets[.resistance] == 6)
        #expect(copy.extraTargets == world.entry.extraTargets)
    }

    @Test("A duped block keeps its own rest, not the routine default")
    func dupeCopiesRestOverride() throws {
        let context = ModelContext(try makeContainer())
        let world = try makeWorld(context: context)
        // The routine rests 60; this block deliberately rests 15.
        world.routine.restSeconds = 60
        world.group.restSecondsOverride = 15
        try context.save()

        let copy = try #require(
            world.routine.duplicateExercise(world.entry, in: world.group, context: context)
        )
        let copyGroup = try #require(copy.group)
        #expect(copyGroup.restSecondsOverride == 15)
        // Sets travel too — the copy is the same block, one slot down.
        #expect(copyGroup.sets == world.group.sets)
        #expect(copyGroup.order == world.group.order + 1)
    }

    /// A block with NO override must not acquire one: `nil` is meaningful
    /// (it means "use the routine's rest"), so copying it as a value rather
    /// than defaulting it is part of the contract.
    @Test("No override stays no override")
    func dupeKeepsAbsentOverrideAbsent() throws {
        let context = ModelContext(try makeContainer())
        let world = try makeWorld(context: context)
        world.group.restSecondsOverride = nil
        try context.save()

        let copy = try #require(
            world.routine.duplicateExercise(world.entry, in: world.group, context: context)
        )
        #expect(copy.group?.restSecondsOverride == nil)
    }

    /// The accessor the fix hangs on. If a seventh target field is ever
    /// added, this is what fails rather than a copy site quietly dropping it.
    @Test("RoutineExercise.targets round-trips every field")
    func targetsRoundTrip() throws {
        let context = ModelContext(try makeContainer())
        let world = try makeWorld(context: context)
        world.entry.weight = 20
        world.entry.reps = 8
        world.entry.repsUpper = nil
        world.entry.durationSeconds = 120
        world.entry.heartRateTarget = .range(lowerBPM: 120, upperBPM: 140)
        world.entry.extraTargets = [.pace: 300]

        let snapshot = world.entry.targets
        // Wipe, then restore from the snapshot alone.
        world.entry.targets = Exercise.AddTimeTargets(
            weight: nil, reps: nil, repsUpper: nil,
            durationSeconds: nil, heartRateTargetData: nil, extraTargets: [:]
        )
        #expect(world.entry.weight == nil)
        #expect(world.entry.extraTargets.isEmpty)

        world.entry.targets = snapshot
        #expect(world.entry.weight == 20)
        #expect(world.entry.reps == 8)
        #expect(world.entry.durationSeconds == 120)
        #expect(world.entry.heartRateTarget == .range(lowerBPM: 120, upperBPM: 140))
        #expect(world.entry.extraTargets[.pace] == 300)
    }
}

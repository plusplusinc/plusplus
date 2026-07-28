import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// Multiple muscle groups per exercise (2026-07-28): the draft's selection
/// rules, and the model's explicit-list-vs-catalog resolution — the part
/// that decides whether a catalog improvement reaches an existing store or
/// silently overwrites what someone chose.
@Suite("Muscle group selection")
struct MuscleGroupSelectionTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("musclegroups-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Draft selection

    @Test("Toggling adds in selection order and keeps the first as primary")
    func selectionOrder() {
        let draft = ExerciseDraft()
        draft.muscleGroups = [.chest]
        draft.toggleMuscleGroup(.triceps)
        draft.toggleMuscleGroup(.shoulders)
        #expect(draft.muscleGroups == [.chest, .triceps, .shoulders])
        #expect(draft.muscleGroup == .chest)

        // Removing a middle group leaves the rest in place.
        draft.toggleMuscleGroup(.triceps)
        #expect(draft.muscleGroups == [.chest, .shoulders])
        #expect(draft.muscleGroup == .chest)
    }

    @Test("Dropping the primary promotes the next, it doesn't reshuffle")
    func primaryPromotion() {
        let draft = ExerciseDraft()
        draft.muscleGroups = [.chest, .triceps, .shoulders]
        draft.toggleMuscleGroup(.chest)
        #expect(draft.muscleGroups == [.triceps, .shoulders])
        #expect(draft.muscleGroup == .triceps)
    }

    @Test("The last group can't be deselected")
    func keepsAtLeastOne() {
        let draft = ExerciseDraft()
        draft.muscleGroups = [.core]
        draft.toggleMuscleGroup(.core)
        #expect(draft.muscleGroups == [.core], "an exercise with no muscle group has nothing to rank or export")
    }

    @Test("The discard-guard fingerprint notices a muscle-group edit")
    func fingerprintTracksGroups() {
        let draft = ExerciseDraft()
        draft.name = "Probe"
        draft.muscleGroups = [.chest]
        let before = draft.fingerprint
        draft.toggleMuscleGroup(.triceps)
        #expect(draft.fingerprint != before)
    }

    // MARK: - Model resolution

    @Test("A custom exercise resolves to its own single group by default")
    func customDefault() throws {
        let context = ModelContext(try makeContainer())
        let exercise = Exercise(name: "Probe Move", muscleGroup: .core)
        context.insert(exercise)
        #expect(exercise.muscleGroups == [.core])
        #expect(exercise.explicitMuscleGroups == nil, "nothing stored means nothing to export")
    }

    @Test("A built-in follows the catalog with no stored list")
    func builtInFollowsCatalog() throws {
        let context = ModelContext(try makeContainer())
        let definition = try #require(SeedData.builtInDefinition(named: "Bench Press"))
        #expect(definition.muscleGroups.count > 1, "the catalog authors secondaries")
        #expect(definition.muscleGroup == definition.muscleGroups[0])

        // Seeded the way SeedData seeds: the single column only. The list
        // resolves from the catalog, so authoring reaches existing stores
        // with zero writes (the metricProfile precedent).
        let exercise = Exercise(name: "Bench Press", muscleGroup: definition.muscleGroup, isBuiltIn: true)
        context.insert(exercise)
        #expect(exercise.explicitMuscleGroups == nil)
        #expect(exercise.muscleGroups == definition.muscleGroups)
    }

    @Test("Pruning a built-in to one group sticks instead of re-inheriting")
    func pruningSticks() throws {
        let context = ModelContext(try makeContainer())
        let definition = try #require(SeedData.builtInDefinition(named: "Bench Press"))
        let exercise = Exercise(name: "Bench Press", muscleGroup: definition.muscleGroup, isBuiltIn: true)
        context.insert(exercise)

        exercise.muscleGroups = [.chest]
        // The regression this guards: a one-element list that stored
        // nothing would fall straight back through to the catalog, so the
        // secondaries someone just removed would reappear on the next read.
        #expect(exercise.muscleGroups == [.chest])
        #expect(exercise.explicitMuscleGroups == [.chest])
    }

    @Test("Setting the list re-stamps the primary column")
    func primaryStaysInStep() throws {
        let context = ModelContext(try makeContainer())
        let exercise = Exercise(name: "Probe Move", muscleGroup: .chest)
        context.insert(exercise)
        exercise.muscleGroups = [.back, .biceps]
        #expect(exercise.muscleGroup == .back, "single-group readers must never disagree with the list")
        #expect(exercise.muscleGroups == [.back, .biceps])
    }

    @Test("The draft writes nothing when the selection matches what resolves anyway")
    func matchingSelectionStaysUnstored() throws {
        let context = ModelContext(try makeContainer())
        let definition = try #require(SeedData.builtInDefinition(named: "Bench Press"))
        let exercise = Exercise(name: "Bench Press", muscleGroup: definition.muscleGroup, isBuiltIn: true)
        context.insert(exercise)

        let draft = ExerciseDraft(from: exercise)
        #expect(draft.muscleGroups == definition.muscleGroups)
        draft.apply(to: exercise)
        #expect(exercise.explicitMuscleGroups == nil, "opening and saving an untouched built-in must not pin it")

        // An actual change does store, so it exports and survives a restore.
        draft.toggleMuscleGroup(.core)
        draft.apply(to: exercise)
        #expect(exercise.explicitMuscleGroups == definition.muscleGroups + [.core])
    }

    @Test("A custom exercise's extra groups store and survive a redraft")
    func customMultiGroup() throws {
        let context = ModelContext(try makeContainer())
        let exercise = Exercise(name: "Probe Move", muscleGroup: .chest)
        context.insert(exercise)

        let draft = ExerciseDraft(from: exercise)
        draft.name = "Probe Move"
        draft.toggleMuscleGroup(.triceps)
        draft.apply(to: exercise)
        #expect(exercise.muscleGroups == [.chest, .triceps])
        #expect(ExerciseDraft(from: exercise).muscleGroups == [.chest, .triceps])
    }

    // MARK: - What the groups feed

    @Test("Search reaches a secondary group, not just the primary")
    func searchReachesSecondaries() throws {
        let context = ModelContext(try makeContainer())
        let exercise = Exercise(name: "Bench Press", muscleGroup: .chest)
        context.insert(exercise)
        exercise.muscleGroups = [.chest, .triceps]
        let haystack = ExerciseFilterState.searchHaystack(exercise).lowercased()
        #expect(haystack.contains("chest"))
        #expect(haystack.contains("triceps"), "typing a muscle must find the moves that work it")
    }

    @Test("Swap suggestions include a move that shares only a secondary")
    func swapPoolWidens() throws {
        let context = ModelContext(try makeContainer())
        let bench = Exercise(name: "Probe Bench", muscleGroup: .chest)
        let dip = Exercise(name: "Probe Dip", muscleGroup: .triceps)
        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)
        for exercise in [bench, dip, curl] { context.insert(exercise) }
        bench.muscleGroups = [.chest, .triceps]
        dip.muscleGroups = [.triceps, .chest]

        let suggestions = ExerciseFilterState.swapSuggestions(
            for: bench, in: [bench, dip, curl], kit: []
        )
        #expect(suggestions.contains { $0.name == "Probe Dip" }, "a dip is a real bench substitute")
        #expect(!suggestions.contains { $0.name == "Probe Curl" }, "sharing nothing stays out")
    }

    @Test("The kit-doable pool stays on the primary")
    func kitPoolStaysNarrow() throws {
        let context = ModelContext(try makeContainer())
        let bench = Exercise(name: "Probe Bench", muscleGroup: .chest)
        let pushdown = Exercise(name: "Probe Pushdown", muscleGroup: .triceps)
        for exercise in [bench, pushdown] { context.insert(exercise) }
        bench.muscleGroups = [.chest, .triceps]

        // This list is sorted by name with no similarity ranking to protect
        // quality, so widening it would seat a pushdown among the offered
        // replacements for a bench press.
        let alternatives = ExerciseFilterState.kitDoableAlternatives(
            for: bench, in: [bench, pushdown], kit: []
        )
        #expect(alternatives.isEmpty)
    }
}

import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("ExerciseFilterState")
struct ExerciseFilterTests {
    /// Every fixture exercise's gear — passed as `available` so the
    /// availability hide never fires in the filtering tests (they're
    /// about search/muscle/equipment selection, not availability).
    private let fixtureGear: Set<String> = ["Barbell", "Dumbbells", "Cable Machine"]

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exercisefilter-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeExercises(context: ModelContext) -> (barbell: Equipment, dumbbells: Equipment, cable: Equipment, exercises: [Exercise]) {
        let barbell = Equipment(name: "Barbell", isBuiltIn: true)
        let dumbbells = Equipment(name: "Dumbbells", isBuiltIn: true)
        let cable = Equipment(name: "Cable Machine", isBuiltIn: true)
        context.insert(barbell)
        context.insert(dumbbells)
        context.insert(cable)

        let benchPress = Exercise(name: "Probe Press", muscleGroup: .chest)
        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)
        let cableFly = Exercise(name: "Probe Fly", muscleGroup: .chest)
        let pushUp = Exercise(name: "Probe Push", muscleGroup: .chest)
        let squat = Exercise(name: "Probe Squat", muscleGroup: .quads)
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)

        let exercises = [benchPress, curl, cableFly, pushUp, squat, plank]
        for e in exercises { context.insert(e) }
        // Post-insert relationship assignment — pre-insert loses
        // nondeterministically (the #186/CI seeder bug).
        benchPress.equipment = [barbell]
        curl.equipment = [dumbbells]
        cableFly.equipment = [cable]
        squat.equipment = [barbell]
        return (barbell, dumbbells, cable, exercises)
    }

    @Test func noFiltersReturnsAllSortedAlphabetically() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        #expect(result.count == 6)
        #expect(result.first?.name == "Probe Curl")
        #expect(result.last?.name == "Probe Squat")
    }

    @Test func searchByNameCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.searchText = "curl"
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        #expect(result.count == 1)
        #expect(result.first?.name == "Probe Curl")
    }

    @Test func singleMuscleGroupFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedMuscleGroups = [.chest]
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.muscleGroup == .chest })
    }

    @Test func multipleMuscleGroupsUnion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedMuscleGroups = [.chest, .biceps]
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        #expect(result.count == 4)
    }

    @Test func singleEquipmentFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (barbell, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedEquipment = [barbell]
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        // Probe Press (barbell) + Squat (barbell)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.equipment.contains(barbell) })
    }

    @Test func bodyweightExcludedWhenEquipmentFilterActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (barbell, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedEquipment = [barbell]
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        // Push-Up and Plank have no equipment — should be excluded
        #expect(!result.contains { $0.name == "Probe Push" })
        #expect(!result.contains { $0.name == "Probe Hold" })
    }

    @Test func bodyweightIncludedWhenNoEquipmentFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        #expect(result.contains { $0.name == "Probe Push" })
        #expect(result.contains { $0.name == "Probe Hold" })
    }

    @Test func crossFilterIntersection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (barbell, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedMuscleGroups = [.chest]
        filter.selectedEquipment = [barbell]
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        // Only Probe Press matches both chest + barbell
        #expect(result.count == 1)
        #expect(result.first?.name == "Probe Press")
    }

    @Test func searchPlusFilterCombined() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.searchText = "press"
        filter.selectedMuscleGroups = [.chest]
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        #expect(result.count == 1)
        #expect(result.first?.name == "Probe Press")
    }

    @Test func searchForgivesTyposAndRanksLiteralFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        // Transposed letters still find the one press.
        filter.searchText = "prses"
        let typo = filter.filteredExercises(from: exercises, kitNames: fixtureGear)
        #expect(typo.map(\.name) == ["Probe Press"])

        // Muscle group rides the haystack: "chest" alone surfaces the
        // chest work without any name containing the word.
        filter.searchText = "chest"
        let byMuscle = filter.filteredExercises(from: exercises, kitNames: fixtureGear)
        #expect(Set(byMuscle.map(\.name)) == ["Probe Press", "Probe Fly", "Probe Push"])
    }

    @Test func emptySearchMatchesAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.searchText = ""
        let result = filter.filteredExercises(from: exercises, kitNames: fixtureGear)

        #expect(result.count == 6)
    }

    /// Kit availability is no longer a FILTER (2026-07-25): the catalog view
    /// shows the whole catalog and partitions on `missingEquipment` (empty ==
    /// doable) into a collapsible "require more equipment" group. Assert the
    /// primitive that drives that partition + the row cue.
    @Test func missingEquipmentReportsTheGap() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        // Only dumbbells in the kit.
        let kit: Set<String> = ["Dumbbells"]
        let filter = ExerciseFilterState()

        // The whole catalog is present regardless of the kit.
        let all = filter.filteredExercises(from: exercises, kitNames: kit)
        #expect(all.contains { $0.name == "Probe Press" }, "barbell work still shows")

        let press = try #require(exercises.first { $0.name == "Probe Press" })
        let curl = try #require(exercises.first { $0.name == "Probe Curl" })
        let push = try #require(exercises.first { $0.name == "Probe Push" })
        // Barbell work is missing gear; dumbbell + bodyweight are doable.
        #expect(ExerciseFilterState.missingEquipment(for: press, available: kit) == ["Barbell"])
        #expect(ExerciseFilterState.missingEquipment(for: curl, available: kit).isEmpty)
        #expect(ExerciseFilterState.missingEquipment(for: push, available: kit).isEmpty)
    }

    // MARK: - Create-from-here prefill

    @Test func prefillNameIsTrimmedSearch() {
        let filter = ExerciseFilterState()
        #expect(filter.prefillName == "")

        filter.searchText = "  Probe Pullover "
        #expect(filter.prefillName == "Probe Pullover")
    }

    @Test func prefillMuscleGroupOnlyWhenExactlyOneFiltered() {
        let filter = ExerciseFilterState()
        #expect(filter.prefillMuscleGroup == nil)

        filter.selectedMuscleGroups = [.chest]
        #expect(filter.prefillMuscleGroup == .chest)

        filter.selectedMuscleGroups = [.chest, .biceps]
        #expect(filter.prefillMuscleGroup == nil, "a multi-select is ambiguous — the editor keeps its own default")
    }

    /// The filter state outlives picker presentations, so a just-deleted
    /// gear item can linger in the selection (bug hunt B1). The read
    /// side already guards this; the prefill is the first WRITE path
    /// and must never seed a deleted model into a new exercise.
    @Test func prefillEquipmentDropsDeletedGear() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (barbell, dumbbells, _, _) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedEquipment = [barbell, dumbbells]
        context.delete(dumbbells)

        #expect(filter.prefillEquipment == [barbell])
    }
}

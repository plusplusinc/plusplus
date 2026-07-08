import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("ExerciseFilterState")
struct ExerciseFilterTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
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

        let benchPress = Exercise(name: "Bench Press", muscleGroup: .chest, equipment: [barbell])
        let curl = Exercise(name: "Dumbbell Curl", muscleGroup: .biceps, equipment: [dumbbells])
        let cableFly = Exercise(name: "Cable Fly", muscleGroup: .chest, equipment: [cable])
        let pushUp = Exercise(name: "Push-Up", muscleGroup: .chest)
        let squat = Exercise(name: "Squat", muscleGroup: .quads, equipment: [barbell])
        let plank = Exercise(name: "Plank", muscleGroup: .core, exerciseType: .duration)

        let exercises = [benchPress, curl, cableFly, pushUp, squat, plank]
        for e in exercises { context.insert(e) }
        return (barbell, dumbbells, cable, exercises)
    }

    @Test func noFiltersReturnsAllSortedAlphabetically() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        let result = filter.filteredExercises(from: exercises)

        #expect(result.count == 6)
        #expect(result.first?.name == "Bench Press")
        #expect(result.last?.name == "Squat")
    }

    @Test func searchByNameCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.searchText = "curl"
        let result = filter.filteredExercises(from: exercises)

        #expect(result.count == 1)
        #expect(result.first?.name == "Dumbbell Curl")
    }

    @Test func singleMuscleGroupFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedMuscleGroups = [.chest]
        let result = filter.filteredExercises(from: exercises)

        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.muscleGroup == .chest })
    }

    @Test func multipleMuscleGroupsUnion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedMuscleGroups = [.chest, .biceps]
        let result = filter.filteredExercises(from: exercises)

        #expect(result.count == 4)
    }

    @Test func singleEquipmentFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (barbell, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedEquipment = [barbell]
        let result = filter.filteredExercises(from: exercises)

        // Bench Press (barbell) + Squat (barbell)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.equipment.contains(barbell) })
    }

    @Test func bodyweightExcludedWhenEquipmentFilterActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (barbell, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedEquipment = [barbell]
        let result = filter.filteredExercises(from: exercises)

        // Push-Up and Plank have no equipment — should be excluded
        #expect(!result.contains { $0.name == "Push-Up" })
        #expect(!result.contains { $0.name == "Plank" })
    }

    @Test func bodyweightIncludedWhenNoEquipmentFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        let result = filter.filteredExercises(from: exercises)

        #expect(result.contains { $0.name == "Push-Up" })
        #expect(result.contains { $0.name == "Plank" })
    }

    @Test func crossFilterIntersection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (barbell, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.selectedMuscleGroups = [.chest]
        filter.selectedEquipment = [barbell]
        let result = filter.filteredExercises(from: exercises)

        // Only Bench Press matches both chest + barbell
        #expect(result.count == 1)
        #expect(result.first?.name == "Bench Press")
    }

    @Test func searchPlusFilterCombined() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.searchText = "press"
        filter.selectedMuscleGroups = [.chest]
        let result = filter.filteredExercises(from: exercises)

        #expect(result.count == 1)
        #expect(result.first?.name == "Bench Press")
    }

    @Test func emptySearchMatchesAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, _, _, exercises) = makeExercises(context: context)

        let filter = ExerciseFilterState()
        filter.searchText = ""
        let result = filter.filteredExercises(from: exercises)

        #expect(result.count == 6)
    }
}

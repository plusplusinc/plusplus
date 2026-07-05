import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("SeedData")
struct SeedDataTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self, WorkoutExercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func allBuiltInExercisesHaveUniqueNames() {
        let equipment = SeedData.builtInEquipment
        let exercises = SeedData.makeBuiltInExercisesForTesting(equipment: equipment)
        let names = exercises.map(\.name)
        #expect(Set(names).count == names.count, "Duplicate exercise names found")
    }

    @Test func allBuiltInEquipmentHaveUniqueNames() {
        let equipment = SeedData.builtInEquipment
        let names = equipment.map(\.name)
        #expect(Set(names).count == names.count, "Duplicate equipment names found")
    }

    @Test func seedDataCoversAllMuscleGroups() {
        let equipment = SeedData.builtInEquipment
        let exercises = SeedData.makeBuiltInExercisesForTesting(equipment: equipment)
        let coveredGroups = Set(exercises.map(\.muscleGroup))
        let allGroups = Set(MuscleGroup.allCases)
        let missing = allGroups.subtracting(coveredGroups)
        #expect(missing.isEmpty, "Missing muscle groups: \(missing)")
    }

    @Test func loadIfNeededInsertsOnFirstRun() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        SeedData.loadIfNeeded(context: context)

        let exerciseCount = try context.fetchCount(FetchDescriptor<Exercise>())
        let equipmentCount = try context.fetchCount(FetchDescriptor<Equipment>())
        #expect(exerciseCount == 27)
        #expect(equipmentCount == 13)
    }

    @Test func loadIfNeededDoesNotDuplicateOnSecondRun() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        SeedData.loadIfNeeded(context: context)
        SeedData.loadIfNeeded(context: context)

        let exerciseCount = try context.fetchCount(FetchDescriptor<Exercise>())
        let equipmentCount = try context.fetchCount(FetchDescriptor<Equipment>())
        #expect(exerciseCount == 27)
        #expect(equipmentCount == 13)
    }

    @Test func allSeededExercisesAreBuiltIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let allBuiltIn = exercises.allSatisfy(\.isBuiltIn)
        #expect(allBuiltIn)
    }

    @Test func allSeededEquipmentAreBuiltIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        SeedData.loadIfNeeded(context: context)

        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        let allBuiltIn = equipment.allSatisfy(\.isBuiltIn)
        #expect(allBuiltIn)
    }
}

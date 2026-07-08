import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("SeedData")
struct SeedDataTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// #186: Dave's store surfaced Bench Press as bodyweight. The seed
    /// itself is correct — these assertions keep it that way for the
    /// known-tricky cases.
    @Test func equipmentRequirementsAreTrueByDefault() {
        let equipment = SeedData.builtInEquipment
        let exercises = SeedData.makeBuiltInExercisesForTesting(equipment: equipment)
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })

        func requires(_ name: String, _ expected: Set<String>) {
            let actual = Set(byName[name]?.equipment.map(\.name) ?? [])
            #expect(actual == expected, "\(name) should require \(expected), got \(actual)")
        }

        requires("Bench Press", ["Barbell", "Bench"])
        requires("Squat", ["Barbell", "Squat Rack"])
        requires("Cable Fly", ["Cable Machine"])
        requires("Cable Row", ["Cable Machine"])
        requires("Tricep Pushdown", ["Cable Machine"])
        requires("Face Pull", ["Cable Machine"])
        requires("Lat Pulldown", ["Lat Pulldown Machine"])
        requires("Pull-Up", ["Pull-Up Bar"])
        requires("Incline Dumbbell Press", ["Dumbbells", "Bench"])
        requires("Hip Thrust", ["Barbell", "Bench"])
        requires("Kettlebell Swing", ["Kettlebell"])
        // Genuinely bodyweight stays bodyweight.
        requires("Push-Up", [])
        requires("Plank", [])
        requires("Burpee", [])
    }

    /// #185: fresh installs seed the catalog, not the library — and the
    /// populate step adds exactly what the owned equipment supports.
    @Test func freshSeedStartsOutOfLibraryAndPopulateRespectsOwnership() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.allSatisfy { !$0.inLibrary })

        // Own only a pull-up bar: bodyweight + pull-up work populates,
        // barbell work doesn't.
        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        for item in equipment {
            item.inLibrary = item.name == "Pull-Up Bar"
        }
        let added = SeedData.populateLibraryFromEquipment(context: context)
        #expect(added > 0)
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        #expect(byName["Pull-Up"]?.inLibrary == true)
        #expect(byName["Push-Up"]?.inLibrary == true)
        #expect(byName["Bench Press"]?.inLibrary == false)
    }

    @Test func repairRestoresEmptyBuiltInEquipment() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bench = exercises.first { $0.name == "Bench Press" }!
        let pushUp = exercises.first { $0.name == "Push-Up" }!
        // Simulate the field-observed loss.
        bench.equipment = []

        UserDefaults.standard.removeObject(forKey: SeedData.equipmentRepairKey)
        SeedData.repairBuiltInEquipmentIfNeeded(context: context)
        defer { UserDefaults.standard.removeObject(forKey: SeedData.equipmentRepairKey) }

        #expect(Set(bench.equipment.map(\.name)) == ["Barbell", "Bench"])
        #expect(pushUp.equipment.isEmpty)
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

import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// `.serialized`: the populate test failed three separate CI runs with
/// Bench Press's equipment mysteriously empty — through a unique-name fix
/// AND a unique-on-disk-store fix, so plain store sharing is ruled out.
/// Only this suite both mutates that relationship (the repair test) and
/// builds containerless model graphs (the definition tests); running its
/// tests one at a time closes every intra-suite channel while the
/// precondition assert below pins down the corruption point if it
/// somehow survives.
@Suite("SeedData", .serialized)
struct SeedDataTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        // In-memory configurations SHARE state across containers in one
        // process — even uniquely NAMED ones (proved twice on CI
        // 2026-07-08: the repair test emptied Bench Press's equipment
        // under the populate test both before and after a naming fix).
        // A throwaway on-disk store per container is the real isolation.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-tests-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
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

        // Diagnostics for the CI-only corruption: bracket the equipment
        // mutation loop so a failure names its mechanism. Point A failing
        // means the seed itself lost the relationship; A passing and B
        // failing means mutating Equipment.inLibrary (a relationship
        // target with no declared inverse) clears the Exercise side.
        let bench = try #require(exercises.first { $0.name == "Bench Press" })
        #expect(!bench.equipment.isEmpty, "A: corrupted at seed time — \(diagnostics(context: context))")

        // Own only a pull-up bar: bodyweight + pull-up work populates,
        // barbell work doesn't.
        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        for item in equipment {
            item.inLibrary = item.name == "Pull-Up Bar"
        }
        #expect(!bench.equipment.isEmpty, "B: corrupted by the inLibrary mutation loop — \(diagnostics(context: context))")
        let added = SeedData.populateLibraryFromEquipment(context: context)
        #expect(added > 0)
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        #expect(byName["Pull-Up"]?.inLibrary == true)
        #expect(byName["Push-Up"]?.inLibrary == true)
        #expect(byName["Bench Press"]?.inLibrary == false)
    }

    /// What the store actually holds vs what this context's graph says —
    /// read through a FRESH context so faulting starts clean.
    private func diagnostics(context: ModelContext) -> String {
        let fresh = ModelContext(context.container)
        let benches = (try? fresh.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Bench Press" })
        )) ?? []
        let equipmentCount = (try? fresh.fetchCount(FetchDescriptor<Equipment>())) ?? -1
        let described = benches.map { "equip=\($0.equipment.map(\.name).sorted()) inLibrary=\($0.inLibrary)" }
        return "freshContext: benchCount=\(benches.count) \(described.joined(separator: " | ")) equipmentRows=\(equipmentCount)"
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

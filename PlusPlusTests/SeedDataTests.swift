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
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
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
        requires("Incline Dumbbell Press", ["Dumbbells", "Incline Bench"])
        requires("Hip Thrust", ["Barbell", "Bench"])
        requires("Kettlebell Swing", ["Kettlebell"])
        requires("Hack Squat", ["Hack Squat Machine"])
        requires("Skull Crusher", ["EZ Bar", "Bench"])
        // Genuinely bodyweight stays bodyweight.
        requires("Push-Up", [])
        requires("Plank", [])
        requires("Burpee", [])
    }

    /// #185: fresh installs seed the catalog, not the library — and the
    /// populate step adds exactly what the ACTIVE library's gear supports.
    @Test func freshSeedStartsOutOfLibraryAndPopulateRespectsAvailability() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.allSatisfy { !$0.inLibrary })

        // Diagnostics for the CI-only corruption: point A failing means
        // the seed itself lost the relationship.
        let bench = try #require(exercises.first { $0.name == "Bench Press" })
        #expect(!bench.equipment.isEmpty, "A: corrupted at seed time — \(diagnostics(context: context))")

        // A library holding only a pull-up bar: bodyweight + pull-up
        // work populates, barbell work doesn't.
        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        let pullUpBar = try #require(equipment.first { $0.name == "Pull-Up Bar" })
        let library = EquipmentLibrary(name: "Home", order: 0)
        context.insert(library)
        library.equipment = [pullUpBar]
        UserDefaults.standard.removeObject(forKey: EquipmentLibrary.activeIDKey)
        defer { UserDefaults.standard.removeObject(forKey: EquipmentLibrary.activeIDKey) }

        #expect(!bench.equipment.isEmpty, "B: corrupted by the membership mutation — \(diagnostics(context: context))")
        let added = SeedData.populateLibraryFromEquipment(context: context)
        #expect(added > 0)
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        #expect(byName["Pull-Up"]?.inLibrary == true)
        #expect(byName["Push-Up"]?.inLibrary == true)
        #expect(byName["Bench Press"]?.inLibrary == false)
    }

    /// The equipment-libraries migration: a store with no library gets a
    /// "Home" holding the legacy in-library built-ins plus every custom
    /// (customs were always available before libraries). Content-keyed
    /// (zero libraries), so it fires once and never re-clobbers.
    @Test func ensureEquipmentLibraryFoldsLegacyState() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        let bench = try #require(equipment.first { $0.name == "Bench" })
        bench.inLibrary = true
        let custom = Equipment(name: "Probe Home Rig", isBuiltIn: false)
        context.insert(custom)
        try context.save()

        SeedData.ensureEquipmentLibrary(context: context)

        let libraries = try context.fetch(FetchDescriptor<EquipmentLibrary>())
        #expect(libraries.count == 1)
        let home = try #require(libraries.first)
        #expect(home.name == "Home")
        #expect(home.memberNames.contains("Bench"), "in-library built-ins fold in")
        #expect(home.memberNames.contains("Probe Home Rig"), "customs were always available")
        #expect(!home.memberNames.contains("Barbell"), "un-owned built-ins stay out")

        // Idempotent: a second run with a library present is a no-op.
        SeedData.ensureEquipmentLibrary(context: context)
        #expect((try context.fetch(FetchDescriptor<EquipmentLibrary>())).count == 1)
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

    /// #232: equipment ownership is opt-in — a fresh seed owns nothing.
    @Test func freshSeedLeavesEquipmentUnowned() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        #expect(!equipment.isEmpty)
        let allUnowned = equipment.allSatisfy { !$0.inLibrary }
        #expect(allUnowned)
    }

    /// #232: the one-shot reset un-owns built-ins on stores that predate
    /// the opt-in flip, never touches custom gear, and never re-runs —
    /// a re-pick after the reset must not be fought.
    @Test func ownershipResetUnownsBuiltInsOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        let bench = try #require(equipment.first { $0.name == "Bench" })
        bench.inLibrary = true
        let custom = Equipment(name: "Probe Custom Rig", isBuiltIn: false)
        context.insert(custom)
        custom.inLibrary = true

        UserDefaults.standard.removeObject(forKey: SeedData.equipmentOwnershipResetKey)
        UserDefaults.standard.set(true, forKey: SetupState.equipmentDoneKey)
        defer {
            UserDefaults.standard.removeObject(forKey: SeedData.equipmentOwnershipResetKey)
            UserDefaults.standard.removeObject(forKey: SetupState.equipmentDoneKey)
        }
        SeedData.resetEquipmentOwnershipIfNeeded(context: context)

        #expect(!bench.inLibrary)
        #expect(custom.inLibrary, "custom gear is deliberate — the reset never touches it")
        #expect(!SetupState.equipmentDone, "the reset erased the curation the setup flag described")

        bench.inLibrary = true
        SeedData.resetEquipmentOwnershipIfNeeded(context: context)
        #expect(bench.inLibrary, "the reset is keyed; a later re-pick stands")
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
        #expect(exerciseCount == SeedData.builtInExerciseCount)
        #expect(equipmentCount == SeedData.builtInEquipment.count)
    }

    @Test func loadIfNeededDoesNotDuplicateOnSecondRun() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        SeedData.loadIfNeeded(context: context)
        SeedData.loadIfNeeded(context: context)

        let exerciseCount = try context.fetchCount(FetchDescriptor<Exercise>())
        let equipmentCount = try context.fetchCount(FetchDescriptor<Equipment>())
        #expect(exerciseCount == SeedData.builtInExerciseCount)
        #expect(equipmentCount == SeedData.builtInEquipment.count)
    }

    /// #235: every equipment type must gate at least one exercise —
    /// gear with nothing to do is catalog noise.
    @Test func everyEquipmentGatesAnExercise() {
        let gated = Set(SeedData.makeBuiltInExercisesForTesting(equipment: SeedData.builtInEquipment)
            .flatMap { $0.equipment.map(\.name) })
        for item in SeedData.builtInEquipment {
            #expect(gated.contains(item.name), "\(item.name) gates no exercise")
        }
    }

    /// #236: the loadable classification references real catalog names
    /// only (a typo would silently strip a machine's weight step).
    @Test func loadableNamesExistInCatalog() {
        let catalog = Set(SeedData.builtInEquipment.map(\.name))
        for name in SeedData.loadableEquipmentNames {
            #expect(catalog.contains(name), "\(name) is not a catalog equipment name")
        }
    }

    /// #236: a step stored on NON-loadable gear (possible on any
    /// pre-build-32 store — every equipment screen offered the option
    /// then) must not drive exercise stepping. The card is gated now,
    /// so an honored stale value would be invisible and uncorrectable.
    @Test func staleStepOnNonLoadableGearIsInert() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bench = try #require(exercises.first { $0.name == "Bench Press" })
        let equipment = try context.fetch(FetchDescriptor<Equipment>())

        let benchGear = try #require(equipment.first { $0.name == "Bench" })
        benchGear.weightStep = 1
        #expect(bench.weightStepOverride == nil, "a bench holds you, not plates — a stale step on it stays inert")

        let barbell = try #require(equipment.first { $0.name == "Barbell" })
        barbell.weightStep = 2.5
        #expect(bench.weightStepOverride == 2.5)
    }

    /// #95: catalog growth reaches EXISTING stores as a top-up — new
    /// definitions arrive out-of-library, new equipment arrives
    /// un-owned, and the user's curation is untouched.
    @Test func topUpAddsNewDefinitionsWithoutTouchingCuration() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // An "old" store: one built-in the user curated into the
        // library, with its gear owned.
        let bench = Equipment(name: "Bench", isBuiltIn: true)
        context.insert(bench)
        let barbell = Equipment(name: "Barbell", isBuiltIn: true)
        context.insert(barbell)
        let press = Exercise(name: "Bench Press", muscleGroup: .chest, isBuiltIn: true)
        press.inLibrary = true
        context.insert(press)
        press.equipment = [barbell, bench]

        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        #expect(exercises.count == SeedData.builtInExerciseCount)
        #expect(equipment.count == SeedData.builtInEquipment.count)
        // Curation untouched; arrivals join catalog-only and un-owned.
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        #expect(byName["Bench Press"]?.inLibrary == true)
        #expect(byName["Squat"]?.inLibrary == false)
        #expect(equipment.first { $0.name == "Bench" }?.inLibrary == true)
        #expect(equipment.first { $0.name == "Hack Squat Machine" }?.inLibrary == false)
        // And the newcomers carry their requirements.
        #expect(byName["Squat"]?.equipment.isEmpty == false)
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

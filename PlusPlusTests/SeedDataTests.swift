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

    // MARK: - Baked-in null kit (2026-07-21)

    @Test func ensureBodyweightKitCreatesTheNullKit() throws {
        let context = ModelContext(try makeContainer())
        SeedData.ensureEquipmentLibrary(context: context)
        SeedData.ensureBodyweightKit(context: context)

        let libraries = try context.fetch(FetchDescriptor<EquipmentLibrary>())
        let names = Set(libraries.map(\.name))
        #expect(names.contains(EquipmentLibrary.defaultName))
        #expect(names.contains(EquipmentLibrary.bodyweightName))
        let null = libraries.first { $0.name == EquipmentLibrary.bodyweightName }
        #expect(null?.isBodyweight == true)
        #expect(null?.members.isEmpty == true)
    }

    @Test func ensureBodyweightKitIsIdempotent() throws {
        let context = ModelContext(try makeContainer())
        SeedData.ensureEquipmentLibrary(context: context)
        SeedData.ensureBodyweightKit(context: context)
        SeedData.ensureBodyweightKit(context: context)

        let nullKits = try context.fetch(FetchDescriptor<EquipmentLibrary>())
            .filter { $0.name == EquipmentLibrary.bodyweightName }
        #expect(nullKits.count == 1)
    }

    /// The "baked in" guarantee: deleting the null kit brings it back on the
    /// next launch's ensure pass.
    @Test func ensureBodyweightKitRecreatesAfterDeletion() throws {
        let context = ModelContext(try makeContainer())
        SeedData.ensureEquipmentLibrary(context: context)
        SeedData.ensureBodyweightKit(context: context)

        if let null = try context.fetch(FetchDescriptor<EquipmentLibrary>())
            .first(where: { $0.name == EquipmentLibrary.bodyweightName }) {
            context.delete(null)
            try context.save()
        }
        SeedData.ensureBodyweightKit(context: context)

        let nullKits = try context.fetch(FetchDescriptor<EquipmentLibrary>())
            .filter { $0.name == EquipmentLibrary.bodyweightName }
        #expect(nullKits.count == 1)
    }

    /// The null kit is immutable — a membership write no-ops, whatever surface
    /// asks, so it stays a true empty set.
    @Test func nullKitRejectsMembership() throws {
        let context = ModelContext(try makeContainer())
        let null = EquipmentLibrary(name: EquipmentLibrary.bodyweightName, order: 1)
        context.insert(null)
        let probe = Equipment(name: "Probe Barbell", isBuiltIn: false)
        context.insert(probe)
        try context.save()

        null.setMembership(probe, true)
        #expect(null.members.isEmpty, "the null kit is immutable — membership writes must no-op")
    }

    /// The always-present null kit must not count toward "more than one kit
    /// exists" — a user with a single real kit still reads "your kit", while
    /// null being the active scope names it.
    @Test func activeNamePhraseIgnoresTheAlwaysPresentNullKit() throws {
        let context = ModelContext(try makeContainer())
        let main = EquipmentLibrary(name: EquipmentLibrary.defaultName, order: 0)
        let null = EquipmentLibrary(name: EquipmentLibrary.bodyweightName, order: 1)
        context.insert(main)
        context.insert(null)
        try context.save()

        // One real kit + the ever-present null → still the generic possessive.
        #expect(EquipmentLibrary.activeNamePhrase(in: [main, null], storedID: main.uuid.uuidString) == "your kit")
        // null itself active → named (a deliberate scope, not "your kit").
        #expect(EquipmentLibrary.activeNamePhrase(in: [main, null], storedID: null.uuid.uuidString) == EquipmentLibrary.bodyweightName)

        // A second real kit → the active kit's own name.
        let garage = EquipmentLibrary(name: "Garage", order: 2)
        context.insert(garage)
        try context.save()
        #expect(EquipmentLibrary.activeNamePhrase(in: [main, null, garage], storedID: garage.uuid.uuidString) == "Garage")
    }

    /// Whole-catalog successor to #185 (2026-07-17): a fresh install seeds
    /// the entire catalog and favorites nothing, and the seed keeps the
    /// exercise↔equipment relationships intact.
    @Test func freshSeedStartsWithNoFavorites() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(!exercises.isEmpty)
        let noFavorites = exercises.allSatisfy { !$0.isFavorite }
        #expect(noFavorites, "a fresh install favorites nothing")

        // Diagnostics for the CI-only corruption: this failing means the
        // seed itself lost the relationship.
        let bench = try #require(exercises.first { $0.name == "Bench Press" })
        #expect(!bench.equipment.isEmpty, "corrupted at seed time — \(diagnostics(context: context))")
    }

    /// The library→favorites one-shot (2026-07-17): an upgrading store's
    /// in-library built-ins become favorites so the user's curation and
    /// their synced repo's exercise files stay continuous. Keyed, so it
    /// fires once.
    @Test func adoptLibraryAsFavoritesCarriesCuration() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        defer { UserDefaults.standard.removeObject(forKey: SeedData.libraryToFavoritesKey) }
        UserDefaults.standard.removeObject(forKey: SeedData.libraryToFavoritesKey)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        // Simulate an upgrading store: two built-ins were in the library.
        for e in exercises { e.inLibrary = false }
        let press = try #require(exercises.first { $0.name == "Bench Press" })
        let pushUp = try #require(exercises.first { $0.name == "Push-Up" })
        press.inLibrary = true
        pushUp.inLibrary = true
        try context.save()

        SeedData.adoptLibraryAsFavoritesIfNeeded(context: context)
        #expect(press.isFavorite)
        #expect(pushUp.isFavorite)
        let favCount = exercises.filter(\.isFavorite).count
        #expect(favCount == 2, "only the in-library built-ins adopt")

        // Keyed once: a later in-library flag doesn't re-adopt.
        let pullUp = try #require(exercises.first { $0.name == "Pull-Up" })
        pullUp.inLibrary = true
        SeedData.adoptLibraryAsFavoritesIfNeeded(context: context)
        #expect(!pullUp.isFavorite, "the one-shot fires once")
    }

    /// Regression (swift-reviewer, 2026-07-17, on-device-only class): a
    /// catalog TOP-UP on the same launch as the adopt one-shot must NOT
    /// favorite the newly-inserted exercises — only the user's genuinely
    /// curated built-ins adopt. (The seed loop must stamp top-ups
    /// `inLibrary = false`; the model default `true` would make adopt
    /// favorite every catalog addition an upgrader never chose.)
    @Test func adoptDoesNotFavoriteCatalogTopUps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        defer { UserDefaults.standard.removeObject(forKey: SeedData.libraryToFavoritesKey) }
        UserDefaults.standard.removeObject(forKey: SeedData.libraryToFavoritesKey)

        // An "old" store predating catalog growth: one curated built-in
        // in the library, the rest of the catalog absent.
        let curated = Exercise(name: "Bench Press", muscleGroup: .chest, isBuiltIn: true)
        curated.inLibrary = true
        context.insert(curated)
        try context.save()

        // The build's launch order: top-up inserts the rest, then adopt.
        SeedData.loadIfNeeded(context: context)
        SeedData.adoptLibraryAsFavoritesIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let favorited = exercises.filter(\.isFavorite).map(\.name).sorted()
        #expect(favorited == ["Bench Press"], "only the curated built-in adopts; top-ups do not — got \(favorited)")
    }

    /// The all-in-library case (the pre-#185 default) is noise, not
    /// curation — the one-shot favorites nothing.
    @Test func adoptSkipsAllInLibraryDefaultNoise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        defer { UserDefaults.standard.removeObject(forKey: SeedData.libraryToFavoritesKey) }
        UserDefaults.standard.removeObject(forKey: SeedData.libraryToFavoritesKey)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        for e in exercises { e.inLibrary = true }
        try context.save()

        SeedData.adoptLibraryAsFavoritesIfNeeded(context: context)
        let noFavorites = exercises.allSatisfy { !$0.isFavorite }
        #expect(noFavorites, "all-in-library is default noise, not curation")
    }

    /// The equipment-libraries migration: a store with no library gets a
    /// default kit (`main` since 2026-07-17) holding the legacy
    /// in-library built-ins plus every custom (customs were always
    /// available before libraries). Content-keyed (zero libraries), so
    /// it fires once and never re-clobbers.
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
        let kit = try #require(libraries.first)
        #expect(kit.name == "main")
        #expect(kit.name == EquipmentLibrary.defaultName)
        #expect(kit.memberNames.contains("Bench"), "in-library built-ins fold in")
        #expect(kit.memberNames.contains("Probe Home Rig"), "customs were always available")
        #expect(!kit.memberNames.contains("Barbell"), "un-owned built-ins stay out")

        // Idempotent: a second run with a library present is a no-op.
        SeedData.ensureEquipmentLibrary(context: context)
        #expect((try context.fetch(FetchDescriptor<EquipmentLibrary>())).count == 1)
    }

    /// The Home→main one-shot (2026-07-17): renames ONLY a lone,
    /// untouched "Home" default. Multi-kit stores and renamed kits are
    /// deliberate curation — never touched — and the UserDefaults key
    /// makes the pass fire once.
    @Test func renameDefaultKitOneShot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        defer { UserDefaults.standard.removeObject(forKey: SeedData.defaultKitRenameKey) }

        // Lone untouched "Home" → renamed.
        UserDefaults.standard.removeObject(forKey: SeedData.defaultKitRenameKey)
        let home = EquipmentLibrary(name: "Home", order: 0)
        context.insert(home)
        try context.save()
        SeedData.renameDefaultKitIfNeeded(context: context)
        #expect(home.name == "main")

        // Keyed once: a later "Home" (user-created) is never touched.
        let recreated = EquipmentLibrary(name: "Home", order: 1)
        context.insert(recreated)
        try context.save()
        SeedData.renameDefaultKitIfNeeded(context: context)
        #expect(recreated.name == "Home")
    }

    @Test func renameDefaultKitSkipsCuratedStores() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        defer { UserDefaults.standard.removeObject(forKey: SeedData.defaultKitRenameKey) }

        // A renamed lone kit is curation.
        UserDefaults.standard.removeObject(forKey: SeedData.defaultKitRenameKey)
        let named = EquipmentLibrary(name: "Garage", order: 0)
        context.insert(named)
        try context.save()
        SeedData.renameDefaultKitIfNeeded(context: context)
        #expect(named.name == "Garage")

        // Multi-kit stores keep their "Home" even when one exists.
        UserDefaults.standard.removeObject(forKey: SeedData.defaultKitRenameKey)
        let home = EquipmentLibrary(name: "Home", order: 1)
        context.insert(home)
        try context.save()
        SeedData.renameDefaultKitIfNeeded(context: context)
        #expect(home.name == "Home")
    }

    /// Full accounting for the catalog's type facet (the FormCues
    /// pattern): every built-in name has exactly one category, and the
    /// table names no phantom gear — catalog growth can't silently skip
    /// the facet or orphan a row.
    @Test func equipmentCategoryTableCoversTheCatalog() {
        let names = Set(SeedData.builtInEquipment.map(\.name))
        let categorized = Set(SeedData.equipmentCategories.keys)
        #expect(names.subtracting(categorized).isEmpty, "uncategorized gear: \(names.subtracting(categorized).sorted())")
        #expect(categorized.subtracting(names).isEmpty, "phantom table entries: \(categorized.subtracting(names).sorted())")
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

    /// Equipment audit (2026-07-15): the one-shot sync upgrades rows
    /// still at their OLD canonical requirements (Cycling was
    /// bodyweight, the landmine pair lacked its barbell), never touches
    /// a user's customization, and never re-runs.
    @Test func equipmentRequirementsSyncUpgradesOldCanonicalRowsOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let cycling = try #require(exercises.first { $0.name == "Cycling" })
        let landmineRow = try #require(exercises.first { $0.name == "Landmine Row" })
        let landminePress = try #require(exercises.first { $0.name == "Landmine Press" })
        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        let landmine = try #require(equipment.first { $0.name == "Landmine" })
        let kettlebell = try #require(equipment.first { $0.name == "Kettlebell" })

        // Simulate a store seeded BEFORE the audit: Cycling bodyweight,
        // landmine work missing its barbell — and one row a user
        // customized away from the old canonical (kettlebell landmine
        // press, why not), which must survive untouched.
        cycling.equipment = []
        landmineRow.equipment = [landmine]
        landminePress.equipment = [landmine, kettlebell]
        try context.save()

        UserDefaults.standard.removeObject(forKey: SeedData.equipmentRequirementsSyncKey)
        defer { UserDefaults.standard.removeObject(forKey: SeedData.equipmentRequirementsSyncKey) }
        SeedData.syncRevisedEquipmentRequirementsIfNeeded(context: context)

        #expect(Set(cycling.equipment.map(\.name)) == ["Bicycle"])
        #expect(Set(landmineRow.equipment.map(\.name)) == ["Barbell", "Landmine"])
        #expect(Set(landminePress.equipment.map(\.name)) == ["Kettlebell", "Landmine"], "customized rows are never rewritten")

        // One-shot: a user who then strips the restored gear isn't fought.
        cycling.equipment = []
        SeedData.syncRevisedEquipmentRequirementsIfNeeded(context: context)
        #expect(cycling.equipment.isEmpty)
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
        press.isFavorite = true
        context.insert(press)
        press.equipment = [barbell, bench]

        SeedData.loadIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        #expect(exercises.count == SeedData.builtInExerciseCount)
        #expect(equipment.count == SeedData.builtInEquipment.count)
        // Favorites untouched; arrivals join unfavorited; equipment
        // top-up stays catalog-only and un-owned (the kept channel).
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        #expect(byName["Bench Press"]?.isFavorite == true)
        #expect(byName["Squat"]?.isFavorite == false)
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

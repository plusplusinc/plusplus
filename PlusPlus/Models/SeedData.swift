import Foundation
import SwiftData
import PlusPlusKit

enum SeedData {
    /// `populateLibrary: false` (#185, extended to equipment in #232)
    /// seeds the whole catalog OUT of the library: a fresh install's
    /// Exercises AND Equipment tabs are empty — ownership is an opt-in
    /// statement (owning everything means the filter says nothing), and
    /// the catalog stays fully browsable either way. `populateLibrary`
    /// is the smoke tests' shortcut to a usable pre-filled store and
    /// only meaningful on a fresh one.
    /// Top-up seeder (#95): inserts whatever the definitions table has
    /// that the store doesn't, so catalog growth reaches existing
    /// installs — user edits and curation are never touched (matching
    /// is by name; nothing is updated or removed).
    static func loadIfNeeded(context: ModelContext, populateLibrary: Bool = false) {
        let existingExercises = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []
        let existingExerciseNames = Set(existingExercises.map { $0.name.lowercased() })
        // Fresh install = no built-in exercises yet. Distinguishes the
        // equipment policy below.
        let isFreshStore = existingExercises.isEmpty

        let allEquipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        var equipmentByName = Dictionary(
            allEquipment.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        for item in builtInEquipment where equipmentByName[item.name.lowercased()] == nil {
            // Un-owned like the exercises (#232): the setup step and the
            // Equipment tab's empty state are the opt-in. Catalog growth
            // never grants ownership to an existing store either.
            item.inLibrary = isFreshStore && populateLibrary
            context.insert(item)
            equipmentByName[item.name.lowercased()] = item
        }

        // Relationships are assigned AFTER context.insert: assigning
        // them in init, pre-insert, against already-inserted targets
        // loses them nondeterministically — the CI repro (found
        // 2026-07-08 after three wrong theories) and almost certainly
        // #186's unreproducible field loss (Bench Press as bodyweight).
        for def in builtInExerciseDefinitions where !existingExerciseNames.contains(def.name.lowercased()) {
            let exercise = Exercise(
                name: def.name,
                muscleGroup: def.muscleGroup,
                exerciseType: def.exerciseType,
                isBuiltIn: true
            )
            // The whole catalog is browsable regardless (2026-07-17):
            // `inLibrary` is frozen for browsing and curation is
            // `isFavorite`. But this MUST stay accurate — it is the sole
            // input to `adoptLibraryAsFavoritesIfNeeded`, which runs once
            // on the same launch as this top-up. A newly inserted
            // built-in is NOT curation, so it must arrive `false` (like
            // the equipment loop above); leaving the model default
            // `true` would make the adopt bridge favorite every catalog
            // addition an upgrader never chose, and export it (swift-
            // reviewer catch, on-device-only class).
            exercise.inLibrary = isFreshStore && populateLibrary
            context.insert(exercise)
            exercise.equipment = def.equipmentNames.compactMap { equipmentByName[$0.lowercased()] }
        }

        try? context.save()
    }

    // MARK: - Library → favorites adoption (whole-catalog upgrade, 2026-07-17)

    /// One-shot: the exercise library became favorites. An existing
    /// store that had curated a library (adopted built-ins) keeps that
    /// curation — each in-library built-in becomes a favorite — so the
    /// user's picks and their synced repo's exercise files stay
    /// continuous across the export-basis change (the repo now exports
    /// favorited built-ins, not in-library ones). Skips the pre-#185
    /// default-noise case where EVERY built-in is in-library (favoriting
    /// all 247 would say nothing); a fresh install has none in-library
    /// so it no-ops there too.
    static let libraryToFavoritesKey = "libraryToFavorites1"

    static func adoptLibraryAsFavoritesIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: libraryToFavoritesKey) else { return }
        UserDefaults.standard.set(true, forKey: libraryToFavoritesKey)
        let builtIns = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []
        guard !builtIns.isEmpty else { return }
        // All-in-library = the pre-#185 default, not real curation.
        guard !builtIns.allSatisfy(\.inLibrary) else { return }
        for exercise in builtIns where exercise.inLibrary {
            exercise.isFavorite = true
        }
        try? context.save()
    }

    /// Equipment-libraries migration: a store that predates
    /// EquipmentLibrary gets one, named "Home", holding the legacy
    /// single-library state (in-library built-ins plus every custom —
    /// customs were always-available before libraries). Content-keyed,
    /// not UserDefaults-keyed: zero libraries IS the pre-migration
    /// signature, and it must also fire for fresh and in-memory
    /// UI-test stores. Runs AFTER the legacy one-shots (the #232
    /// ownership reset rewrites inLibrary, and this snapshot must see
    /// the result) — PlusPlusApp owns that ordering.
    static func ensureEquipmentLibrary(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<EquipmentLibrary>())) ?? 0
        guard count == 0 else { return }
        let equipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        let library = EquipmentLibrary(name: EquipmentLibrary.defaultName, order: 0)
        // Insert first, assign the relationship after (the pre-insert
        // loss law — this is exactly the seeder's #186 shape).
        context.insert(library)
        library.equipment = equipment.filter { $0.inLibrary || !$0.isBuiltIn }
        try? context.save()
    }

    /// The baked-in no-equipment kit (2026-07-21): every store always carries
    /// `null` alongside `main`, so a bodyweight-only scope is always one tap
    /// away and nobody has to build one. Idempotent by the reserved name (also
    /// how the interchange dedups libraries) and re-created if deleted — the
    /// "baked in" guarantee. Runs AFTER ensureEquipmentLibrary so `main` exists
    /// and takes order 0, leaving `null` as the second option on a fresh store.
    static func ensureBodyweightKit(context: ModelContext) {
        let libraries = (try? context.fetch(FetchDescriptor<EquipmentLibrary>())) ?? []
        guard !libraries.contains(where: { $0.name == EquipmentLibrary.bodyweightName }) else { return }
        let order = (libraries.map(\.order).max() ?? -1) + 1
        let kit = EquipmentLibrary(name: EquipmentLibrary.bodyweightName, order: order)
        context.insert(kit)
        try? context.save()
    }

    /// #155 uuid backfill — ENFORCES UNIQUENESS, not just non-nil. The
    /// routine-family models gained an optional `uuid` (for the tray-flicker
    /// decoupling). It's set in `init`, never via a property-level default,
    /// because SwiftData's lightweight migration stamps a `= UUID()` default
    /// as ONE SHARED CONSTANT across every migrated row — which made all
    /// routines resolve to the same one and the rail render duplicate rows.
    /// So this assigns a fresh uuid to any row whose uuid is nil OR a
    /// duplicate of one already seen, repairing both a clean migration (all
    /// nil) and a store already stamped with the shared default (all equal).
    /// Content-keyed + idempotent: once every row has a distinct uuid it's a
    /// no-op, so it's safe to run every launch.
    static func backfillModelUUIDsIfNeeded(context: ModelContext) {
        var changed = false
        var seen = Set<UUID>()

        func ensureUnique(_ current: UUID?, assign: (UUID) -> Void) {
            if let current, seen.insert(current).inserted { return }
            // nil, or a uuid already used by an earlier row → mint a fresh one.
            var fresh = UUID()
            while !seen.insert(fresh).inserted { fresh = UUID() }
            assign(fresh)
            changed = true
        }

        for routine in (try? context.fetch(FetchDescriptor<Routine>())) ?? [] {
            ensureUnique(routine.uuid) { routine.uuid = $0 }
        }
        for group in (try? context.fetch(FetchDescriptor<ExerciseGroup>())) ?? [] {
            ensureUnique(group.uuid) { group.uuid = $0 }
        }
        for entry in (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? [] {
            ensureUnique(entry.uuid) { entry.uuid = $0 }
        }

        if changed { try? context.save() }
    }

    /// Fold the retired "Stationary Bike" exercise into "Indoor Cycling"
    /// (Dave, build 158: they are the same thing).
    ///
    /// Dropping a definition is not enough on a store that already has the
    /// row — `loadIfNeeded` only ever ADDS what is missing, so both would sit
    /// in the catalog forever, and one of them is probably in the user's
    /// routines and history.
    ///
    /// ⚠️ So this MERGES rather than deletes. The old row is renamed when it
    /// is the only one, which carries every routine entry and every logged
    /// set with it untouched — a rename keeps the same object, so nothing
    /// dangles. When both rows exist the one nothing references is the one
    /// that goes, whichever that is; if both are referenced, both stay and
    /// this does nothing, because merging two histories is not a thing a
    /// launch pass should attempt behind someone's back.
    ///
    /// Content-keyed and idempotent: once no built-in "Stationary Bike"
    /// exercise exists it is a no-op, so it is safe every launch.
    static func mergeIndoorBikeExercises(context: ModelContext) {
        let builtIns = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []
        guard let legacy = builtIns.first(where: { $0.name.lowercased() == "stationary bike" }) else { return }
        let modern = builtIns.first { $0.name.lowercased() == "indoor cycling" }
        // Where a branch below retires the "Stationary Bike" NAME, a
        // quick-start pick keyed to it (build 158 offered it) follows to
        // "Indoor Cycling" instead of vanishing — but ONLY those
        // branches. The both-referenced fall-through keeps the legacy row
        // and its name, and re-pointing a pick at a different exercise
        // the user didn't choose would be worse than the gap.
        let repointPick = { QuickStartPicks.rename(from: "Stationary Bike", to: "Indoor Cycling") }

        guard let modern else {
            // The common case: rename in place. The profile comes with it,
            // since the old row's was the poorer of the two.
            legacy.name = "Indoor Cycling"
            legacy.metricProfile = MetricProfile(
                [.duration, .distance, .resistance, .power, .cadence],
                distanceUnit: .miles
            )
            try? context.save()
            repointPick()
            return
        }

        // Both present. Whichever nothing points at is the duplicate.
        if !isReferenced(legacy, context: context) {
            context.delete(legacy)
            try? context.save()
            repointPick()
        } else if !isReferenced(modern, context: context) {
            context.delete(modern)
            legacy.name = "Indoor Cycling"
            legacy.metricProfile = MetricProfile(
                [.duration, .distance, .resistance, .power, .cadence],
                distanceUnit: .miles
            )
            try? context.save()
            repointPick()
        }
    }

    /// Whether any routine entry or logged set points at this exercise.
    /// `Exercise` declares no inverse for either, so this asks them.
    private static func isReferenced(_ exercise: Exercise, context: ModelContext) -> Bool {
        let entries = (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
        if entries.contains(where: { $0.exercise === exercise }) { return true }
        let logs = (try? context.fetch(FetchDescriptor<SetLog>())) ?? []
        return logs.contains { $0.exercise === exercise }
    }

    /// One-shot ownership reset (#232): equipment seeded fully-owned on
    /// fresh stores until build 32 — backwards, since an all-owned list
    /// filters nothing — and Dave chose to reset existing stores rather
    /// than grandfather the old default. Built-in equipment goes
    /// un-owned once; custom gear (created deliberately) stays. Keyed
    /// so a later re-pick is never fought. PRE-LIBRARIES: it rewrites
    /// the legacy inLibrary flags, so it must run before
    /// ensureEquipmentLibrary snapshots them.
    static let equipmentOwnershipResetKey = "equipmentOwnershipReset1"

    static func resetEquipmentOwnershipIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: equipmentOwnershipResetKey) else { return }
        UserDefaults.standard.set(true, forKey: equipmentOwnershipResetKey)

        let equipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        for item in equipment where item.isBuiltIn && item.inLibrary {
            item.inLibrary = false
        }
        // The setup flag described the curation this just erased — clear
        // it too, so a no-history user gets the setup step back as the
        // re-pick affordance (users with history never see the scaffold;
        // for them the Equipment tab's empty state is the pointer).
        UserDefaults.standard.removeObject(forKey: SetupState.equipmentDoneKey)
        try? context.save()
    }

    /// One-shot repair (#186): Dave's store surfaced built-ins with
    /// EMPTY equipment (Bench Press listed as bodyweight) even though
    /// the seeder's definitions are correct — the loss path predates
    /// build 22 and couldn't be reproduced from code. Built-ins whose
    /// equipment is empty but whose canonical definition requires gear
    /// get their requirements restored from the definitions table.
    /// Runs once (UserDefaults-keyed) so it can't fight a user who
    /// later strips equipment deliberately in the editor.
    static let equipmentRepairKey = "builtInEquipmentRepair1"

    static func repairBuiltInEquipmentIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: equipmentRepairKey) else { return }
        UserDefaults.standard.set(true, forKey: equipmentRepairKey)

        let exercises = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []
        let equipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        let byName = Dictionary(equipment.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        for exercise in exercises where exercise.equipment.isEmpty {
            guard let def = builtInDefinition(named: exercise.name), !def.equipmentNames.isEmpty else { continue }
            exercise.equipment = def.equipmentNames.compactMap { byName[$0.lowercased()] }
        }
        try? context.save()
    }

    /// One-shot definition sync (equipment audit, 2026-07-15): the audit
    /// corrected four catalog rows — Cycling gained the new Bicycle (it
    /// read as "Bodyweight"), Slider Leg Curl its Sliders, and the
    /// landmine pair the Barbell the attachment is useless without. The
    /// top-up seeder never updates existing rows, so stores that predate
    /// the fix still carry the old requirements. This upgrades exactly
    /// the rows still AT the old canonical set — a user's own
    /// customization never matches, so it's never touched — and runs
    /// once (UserDefaults-keyed, the #186 repair pattern) so removing
    /// the restored gear later isn't fought. Must run AFTER loadIfNeeded
    /// (the Bicycle row has to exist to be attached).
    static let equipmentRequirementsSyncKey = "equipmentRequirementsSync1"

    static func syncRevisedEquipmentRequirementsIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: equipmentRequirementsSyncKey) else { return }
        UserDefaults.standard.set(true, forKey: equipmentRequirementsSyncKey)

        // Name → the requirement set the row shipped with BEFORE the audit.
        let previousRequirements: [String: Set<String>] = [
            "Cycling": [],
            "Slider Leg Curl": [],
            "Landmine Row": ["Landmine"],
            "Landmine Press": ["Landmine"],
        ]

        let exercises = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []
        let equipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        let byName = Dictionary(equipment.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        for exercise in exercises {
            guard let previous = previousRequirements[exercise.name],
                  let def = builtInDefinition(named: exercise.name) else { continue }
            let current = Set(exercise.equipment.filter { !$0.isDeleted }.map(\.name))
            guard current == previous else { continue }
            exercise.equipment = def.equipmentNames.compactMap { byName[$0.lowercased()] }
        }
        try? context.save()
    }

    // MARK: - Default kit rename ("Home" → "main", 2026-07-17)

    /// One-shot: the default equipment kit is named `main` now (plain
    /// first reading, git second reading; also activity-neutral where
    /// "Home" wasn't). Renames an existing store's LONE, untouched
    /// default only — a store with multiple kits, or a lone kit not
    /// named "Home", is deliberate curation and is never touched.
    /// Fresh installs get `main` straight from `ensureEquipmentLibrary`
    /// via the renamed constant.
    static let defaultKitRenameKey = "defaultKitRename1"

    static func renameDefaultKitIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: defaultKitRenameKey) else { return }
        UserDefaults.standard.set(true, forKey: defaultKitRenameKey)
        let libraries = (try? context.fetch(FetchDescriptor<EquipmentLibrary>())) ?? []
        guard libraries.count == 1, let lone = libraries.first, lone.name == "Home" else { return }
        lone.name = EquipmentLibrary.defaultName
        try? context.save()
    }
}

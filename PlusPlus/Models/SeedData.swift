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

    // MARK: - Equipment

    // Generic types only, no brand names (#222 — compiled from a sweep
    // of Rogue/Rep/Titan home-gym catalogs and Hammer Strength /
    // Life Fitness / Precor-class commercial lines). Inclusion rule: an
    // item qualifies only if some exercise can genuinely REQUIRE it;
    // pure accessories (straps, chalk, collars, bracing belts) stay
    // out. Near-synonyms map to one type (functional trainer → Cable
    // Machine, prowler → Sled, power tower → its stations, buffalo bar
    // → Cambered Squat Bar). The top-up seeder delivers newcomers to
    // existing stores catalog-only and un-owned (#95).
    static var builtInEquipment: [Equipment] {
        [
            // Free weights + bars
            "Barbell", "EZ Bar", "Trap Bar", "Dumbbells", "Kettlebell",
            "Weight Plate", "Sandbag",
            // Specialty bars
            "Safety Squat Bar", "Swiss Bar", "Cambered Squat Bar",
            "Axle Bar",
            // Racks, benches, stations
            "Squat Rack", "Bench", "Incline Bench", "Decline Bench",
            "Preacher Bench", "Dip Station", "Pull-Up Bar",
            "Back Extension Bench", "Glute-Ham Developer",
            "Reverse Hyper Machine", "Nordic Bench", "Sissy Squat Bench",
            "Captain's Chair", "Plyo Box", "Landmine",
            // Machines — plate-loaded
            "Smith Machine", "T-Bar Row Machine", "Belt Squat Machine",
            "Pendulum Squat Machine", "Pullover Machine",
            // Machines — cable + selectorized
            "Cable Machine", "Leg Press Machine",
            "Lat Pulldown Machine", "Leg Extension Machine",
            "Leg Curl Machine", "Calf Raise Machine", "Hack Squat Machine",
            "Hip Thrust Machine", "Pec Deck Machine", "Chest Press Machine",
            "Shoulder Press Machine", "Seated Row Machine",
            "Hip Abduction Machine", "Hip Adduction Machine",
            "Assisted Pull-Up Machine", "Ab Crunch Machine",
            "Torso Rotation Machine", "Lateral Raise Machine",
            "Bicep Curl Machine", "Tricep Extension Machine",
            "Low Back Extension Machine", "Multi-Hip Machine",
            "Glute Kickback Machine",
            // Cardio (Bicycle = the road bike, like the Weight Vest for
            // Ruck: outdoor gear an exercise genuinely requires)
            "Rowing Machine", "Stationary Bike", "Treadmill", "Air Bike",
            "Ski Erg", "Elliptical", "Stair Climber", "Vertical Climber",
            "Upper Body Ergometer", "Bicycle",
            // Strongman
            "Sled", "Yoke", "Farmers Walk Handles", "Log Bar",
            "Atlas Stone", "Circus Dumbbell", "Husafell Stone", "Tire",
            "Sledgehammer",
            // Gymnastics + calisthenics
            "Suspension Trainer", "Gymnastic Rings", "Parallettes",
            "Climbing Rope", "Peg Board", "Stall Bars",
            // Small equipment
            "Battle Ropes", "Jump Rope", "Medicine Ball", "Slam Ball",
            "Stability Ball", "Balance Trainer", "Ab Wheel",
            "Resistance Band", "Weightlifting Chains", "Dip Belt",
            "Weight Vest", "Sliders", "Macebell", "Steel Club",
            "Bulgarian Bag", "Wrist Roller", "Neck Harness",
            "Hand Gripper", "Heavy Bag", "Agility Ladder",
            "Tibialis Bar", "Slant Board",
        ].map { Equipment(name: $0, isBuiltIn: true) }
    }

    // MARK: - Equipment categories (the catalog's type facet, 2026-07-17)

    /// The equipment catalog's type buckets — user-facing chip labels.
    /// App-side static data like `equipmentProfiles`: no model column,
    /// no migration, no interchange ripple. Customs carry no category
    /// and drop out under a type chip.
    enum EquipmentCategory: String, CaseIterable {
        case freeWeights = "Free weights"
        case machines = "Machines"
        case bandsStraps = "Bands & straps"
        case cardio = "Cardio"
        case bodyweightGear = "Bodyweight equipment"
    }

    /// Every built-in name maps to exactly one category (accounting
    /// enforced by `SeedDataTests` so catalog growth can't silently
    /// skip the facet). Findability rules: a name containing "Machine"
    /// buckets under Machines EXCEPT the Rowing Machine (purpose wins —
    /// it's cardio); strongman implements, thrown/carried loads, and
    /// loading accessories are Free weights; benches, racks, stations,
    /// and bodyweight floor tools are Bodyweight equipment.
    static let equipmentCategories: [String: EquipmentCategory] = {
        var table: [String: EquipmentCategory] = [:]
        let buckets: [(EquipmentCategory, [String])] = [
            (.freeWeights, [
                "Barbell", "EZ Bar", "Trap Bar", "Dumbbells", "Kettlebell",
                "Weight Plate", "Sandbag", "Safety Squat Bar", "Swiss Bar",
                "Cambered Squat Bar", "Axle Bar", "Landmine",
                "Sled", "Yoke", "Farmers Walk Handles", "Log Bar",
                "Atlas Stone", "Circus Dumbbell", "Husafell Stone", "Tire",
                "Sledgehammer", "Weightlifting Chains", "Macebell",
                "Steel Club", "Bulgarian Bag", "Medicine Ball", "Slam Ball",
                "Dip Belt", "Weight Vest", "Wrist Roller",
            ]),
            (.machines, [
                "Smith Machine", "T-Bar Row Machine", "Belt Squat Machine",
                "Pendulum Squat Machine", "Pullover Machine", "Cable Machine",
                "Leg Press Machine", "Lat Pulldown Machine",
                "Leg Extension Machine", "Leg Curl Machine",
                "Calf Raise Machine", "Hack Squat Machine",
                "Hip Thrust Machine", "Pec Deck Machine",
                "Chest Press Machine", "Shoulder Press Machine",
                "Seated Row Machine", "Hip Abduction Machine",
                "Hip Adduction Machine", "Assisted Pull-Up Machine",
                "Ab Crunch Machine", "Torso Rotation Machine",
                "Lateral Raise Machine", "Bicep Curl Machine",
                "Tricep Extension Machine", "Low Back Extension Machine",
                "Multi-Hip Machine", "Glute Kickback Machine",
                "Reverse Hyper Machine",
            ]),
            (.cardio, [
                "Rowing Machine", "Stationary Bike", "Treadmill", "Air Bike",
                "Ski Erg", "Elliptical", "Stair Climber", "Vertical Climber",
                "Upper Body Ergometer", "Bicycle", "Jump Rope",
                "Battle Ropes", "Agility Ladder", "Heavy Bag",
            ]),
            (.bandsStraps, [
                "Suspension Trainer", "Gymnastic Rings", "Resistance Band",
                "Climbing Rope",
            ]),
            (.bodyweightGear, [
                "Squat Rack", "Bench", "Incline Bench", "Decline Bench",
                "Preacher Bench", "Dip Station", "Pull-Up Bar",
                "Back Extension Bench", "Glute-Ham Developer", "Nordic Bench",
                "Sissy Squat Bench", "Captain's Chair", "Plyo Box",
                "Parallettes", "Peg Board", "Stall Bars", "Stability Ball",
                "Balance Trainer", "Ab Wheel", "Sliders", "Neck Harness",
                "Hand Gripper", "Tibialis Bar", "Slant Board",
            ]),
        ]
        for (category, names) in buckets {
            for name in names { table[name] = category }
        }
        return table
    }()

    static func equipmentCategory(named name: String) -> EquipmentCategory? {
        equipmentCategories[name]
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

    // MARK: - Exercises

    // Exposed as internal for testing; use loadIfNeeded for production
    static func makeBuiltInExercisesForTesting(equipment: [Equipment]) -> [Exercise] {
        makeBuiltInExercises(equipment: equipment)
    }

    /// Canonical catalog definition — the "default" a customized
    /// built-in reverts to (#136).
    struct BuiltInExerciseDefinition {
        let name: String
        let muscleGroup: MuscleGroup
        let equipmentNames: [String]
        let exerciseType: ExerciseType
        /// Explicit metric-profile override. nil derives from the
        /// equipment table + type (`suggestedProfile`) — only exercises
        /// whose tracking the rules can't express carry one (Ruck's
        /// mileage on plain strength gear, the no-equipment cardio).
        let metrics: MetricProfile?
        /// Add-time set count (config audit, 2026-07-15). 3 — the classic
        /// strength block — unless the exercise's shape says otherwise:
        /// a stretch is one hold, a mobility drill one pass, a steady
        /// cardio piece one round.
        let defaultSets: Int
        /// Catalog rep prescription where the global 10-rep floor is
        /// never what anyone does (a Turkish get-up is 3, a power clean
        /// 3, a rope climb 3). nil rides the global floor. A user's own
        /// bumped default (#187) always wins over this.
        let defaultReps: Int?
        /// Catalog effort length where the global 45 s floor misses (a
        /// static stretch holds 30 s, a heavy-bag round runs 3 min, an
        /// L-sit survives 20 s). Same precedence as defaultReps.
        let defaultDurationSeconds: Int?
        /// Whether a heart-rate prescription makes sense here. False for
        /// stretches and static holds — a "zone 2 hamstring stretch" is
        /// noise — so their planning/config sheets drop the Target HR
        /// row. A column, not a side table, so a new stretch can't
        /// forget it. Customs always keep the row (the isLoadable
        /// can't-classify-intent rule, applied in Exercise).
        let supportsHeartRate: Bool
    }

    /// Keyed lookup (the builtInProfilesByName pattern) — the resolution
    /// helpers on Exercise hit this per add/sheet-open, so no linear scan.
    private static let definitionsByName: [String: BuiltInExerciseDefinition] = {
        Dictionary(uniqueKeysWithValues: builtInExerciseDefinitions.map { ($0.name, $0) })
    }()

    static func builtInDefinition(named name: String) -> BuiltInExerciseDefinition? {
        definitionsByName[name]
    }

    /// Definition-table size, so tests assert against the table instead
    /// of a hardcoded count that rots every time the catalog grows.
    static var builtInExerciseCount: Int { builtInExerciseDefinitions.count }

    private static func makeBuiltInExercises(equipment: [Equipment]) -> [Exercise] {
        let eq = Dictionary(uniqueKeysWithValues: equipment.map { ($0.name, $0) })
        return builtInExerciseDefinitions.map { def in
            Exercise(
                name: def.name,
                muscleGroup: def.muscleGroup,
                equipment: def.equipmentNames.compactMap { eq[$0] },
                exerciseType: def.exerciseType,
                isBuiltIn: true
            )
        }
    }

    private static let builtInExerciseDefinitions: [BuiltInExerciseDefinition] = {
        func e(_ name: String, _ muscle: MuscleGroup, _ eqNames: [String], _ type: ExerciseType = .weightReps, metrics: MetricProfile? = nil, sets: Int = 3, reps: Int? = nil, seconds: Int? = nil, heartRate: Bool = true) -> BuiltInExerciseDefinition {
            BuiltInExerciseDefinition(name: name, muscleGroup: muscle, equipmentNames: eqNames, exerciseType: type, metrics: metrics, defaultSets: sets, defaultReps: reps, defaultDurationSeconds: seconds, supportsHeartRate: heartRate)
        }
        // The two mobility-work shapes, defined ONCE: a static stretch is
        // a single 30 s hold (the standard prescription — and what the
        // Full Body Stretch routine already prescribes per entry); a
        // dynamic drill is one pass of reps. Neither takes a heart-rate
        // prescription. Static HOLDS that build strength (Plank, Wall
        // Sit) are NOT stretches — they keep their 3-set blocks and
        // declare `heartRate: false` on their own rows.
        func stretch(_ name: String, _ muscle: MuscleGroup) -> BuiltInExerciseDefinition {
            e(name, muscle, [], .duration, sets: 1, seconds: 30, heartRate: false)
        }
        func mobility(_ name: String, _ muscle: MuscleGroup) -> BuiltInExerciseDefinition {
            e(name, muscle, [], sets: 1, heartRate: false)
        }

        return [
            // Chest
            e("Bench Press", .chest, ["Barbell", "Bench"]),
            e("Incline Bench Press", .chest, ["Barbell", "Incline Bench"]),
            e("Dumbbell Bench Press", .chest, ["Dumbbells", "Bench"]),
            e("Incline Dumbbell Press", .chest, ["Dumbbells", "Incline Bench"]),
            e("Machine Chest Press", .chest, ["Chest Press Machine"]),
            e("Smith Machine Bench Press", .chest, ["Smith Machine", "Bench"]),
            e("Dumbbell Fly", .chest, ["Dumbbells", "Bench"]),
            e("Cable Fly", .chest, ["Cable Machine"]),
            e("Low-to-High Cable Fly", .chest, ["Cable Machine"]),
            e("Pec Deck", .chest, ["Pec Deck Machine"]),
            e("Chest Dip", .chest, ["Dip Station"]),
            e("Push-Up", .chest, []),
            e("Deficit Push-Up", .chest, []),
            e("Ring Push-Up", .chest, ["Gymnastic Rings"]),
            e("Band Chest Press", .chest, ["Resistance Band"]),
            e("Svend Press", .chest, ["Weight Plate"]),

            // Back
            e("Deadlift", .back, ["Barbell"]),
            e("Trap Bar Deadlift", .back, ["Trap Bar"]),
            e("Barbell Row", .back, ["Barbell"]),
            e("Pendlay Row", .back, ["Barbell"]),
            e("Dumbbell Row", .back, ["Dumbbells", "Bench"]),
            e("Chest-Supported Row", .back, ["Dumbbells", "Incline Bench"]),
            e("Seated Cable Row", .back, ["Seated Row Machine"]),
            e("Cable Row", .back, ["Cable Machine"]),
            e("Machine Row", .back, ["Seated Row Machine"]),
            // A landmine is a sleeve for a BARBELL — the bar is required
            // (equipment audit; the Chain Bench Press convention).
            e("Landmine Row", .back, ["Barbell", "Landmine"]),
            e("Pull-Up", .back, ["Pull-Up Bar"]),
            e("Chin-Up", .back, ["Pull-Up Bar"]),
            e("Neutral-Grip Pull-Up", .back, ["Pull-Up Bar"]),
            e("Lat Pulldown", .back, ["Lat Pulldown Machine"]),
            e("Straight-Arm Pulldown", .back, ["Cable Machine"]),
            e("Ring Row", .back, ["Gymnastic Rings"]),
            e("Suspension Row", .back, ["Suspension Trainer"]),
            e("Band Pull-Apart", .back, ["Resistance Band"]),
            e("Back Extension", .back, ["Back Extension Bench"]),
            e("Good Morning", .back, ["Barbell"]),

            // Shoulders
            e("Overhead Press", .shoulders, ["Barbell"]),
            e("Seated Dumbbell Press", .shoulders, ["Dumbbells", "Bench"]),
            e("Dumbbell Shoulder Press", .shoulders, ["Dumbbells"]),
            e("Machine Shoulder Press", .shoulders, ["Shoulder Press Machine"]),
            e("Arnold Press", .shoulders, ["Dumbbells"]),
            e("Push Press", .shoulders, ["Barbell"]),
            e("Landmine Press", .shoulders, ["Barbell", "Landmine"]),
            e("Lateral Raise", .shoulders, ["Dumbbells"]),
            e("Cable Lateral Raise", .shoulders, ["Cable Machine"]),
            e("Front Raise", .shoulders, ["Dumbbells"]),
            e("Plate Front Raise", .shoulders, ["Weight Plate"]),
            e("Rear Delt Fly", .shoulders, ["Dumbbells"]),
            e("Reverse Pec Deck", .shoulders, ["Pec Deck Machine"]),
            e("Face Pull", .shoulders, ["Cable Machine"]),
            e("Upright Row", .shoulders, ["Barbell"]),
            e("Barbell Shrug", .shoulders, ["Barbell"]),
            e("Dumbbell Shrug", .shoulders, ["Dumbbells"]),
            e("Pike Push-Up", .shoulders, []),

            // Biceps
            e("Barbell Curl", .biceps, ["Barbell"]),
            e("EZ Bar Curl", .biceps, ["EZ Bar"]),
            e("Dumbbell Curl", .biceps, ["Dumbbells"]),
            e("Hammer Curl", .biceps, ["Dumbbells"]),
            e("Incline Dumbbell Curl", .biceps, ["Dumbbells", "Incline Bench"]),
            e("Preacher Curl", .biceps, ["EZ Bar", "Preacher Bench"]),
            e("Concentration Curl", .biceps, ["Dumbbells", "Bench"]),
            e("Cable Curl", .biceps, ["Cable Machine"]),
            e("Band Curl", .biceps, ["Resistance Band"]),
            e("Zottman Curl", .biceps, ["Dumbbells"]),
            e("Spider Curl", .biceps, ["Dumbbells", "Incline Bench"]),

            // Triceps
            e("Close-Grip Bench Press", .triceps, ["Barbell", "Bench"]),
            e("Tricep Pushdown", .triceps, ["Cable Machine"]),
            e("Rope Pushdown", .triceps, ["Cable Machine"]),
            e("Overhead Tricep Extension", .triceps, ["Dumbbells"]),
            e("Cable Overhead Extension", .triceps, ["Cable Machine"]),
            e("Skull Crusher", .triceps, ["EZ Bar", "Bench"]),
            e("Tricep Dip", .triceps, ["Dip Station"]),
            e("Bench Dip", .triceps, ["Bench"]),
            e("Diamond Push-Up", .triceps, []),
            e("Band Pushdown", .triceps, ["Resistance Band"]),
            e("Tricep Kickback", .triceps, ["Dumbbells"]),

            // Quads
            e("Squat", .quads, ["Barbell", "Squat Rack"]),
            e("Front Squat", .quads, ["Barbell", "Squat Rack"]),
            e("Smith Machine Squat", .quads, ["Smith Machine"]),
            e("Goblet Squat", .quads, ["Dumbbells"]),
            e("Kettlebell Goblet Squat", .quads, ["Kettlebell"]),
            e("Hack Squat", .quads, ["Hack Squat Machine"]),
            e("Leg Press", .quads, ["Leg Press Machine"]),
            e("Leg Extension", .quads, ["Leg Extension Machine"]),
            e("Bulgarian Split Squat", .quads, ["Dumbbells", "Bench"]),
            e("Walking Lunge", .quads, ["Dumbbells"]),
            e("Reverse Lunge", .quads, ["Dumbbells"]),
            e("Step-Up", .quads, ["Dumbbells", "Plyo Box"]),
            e("Box Squat", .quads, ["Barbell", "Squat Rack", "Plyo Box"]),
            e("Bodyweight Squat", .quads, []),
            e("Jump Squat", .quads, []),
            e("Wall Sit", .quads, [], .duration, heartRate: false),
            e("Sissy Squat", .quads, []),

            // Hamstrings
            e("Romanian Deadlift", .hamstrings, ["Barbell"]),
            e("Dumbbell Romanian Deadlift", .hamstrings, ["Dumbbells"]),
            e("Stiff-Leg Deadlift", .hamstrings, ["Barbell"]),
            e("Single-Leg Romanian Deadlift", .hamstrings, ["Dumbbells"]),
            e("Leg Curl", .hamstrings, ["Leg Curl Machine"]),
            // Nordics are near-maximal eccentrics — 5 is a real set.
            e("Nordic Curl", .hamstrings, [], reps: 5),
            e("Glute-Ham Raise", .hamstrings, ["Back Extension Bench"]),
            e("Cable Pull-Through", .hamstrings, ["Cable Machine"]),
            // Sliders required, like Slider Lunge/Body Saw (equipment
            // audit — this one shipped as bodyweight).
            e("Slider Leg Curl", .hamstrings, ["Sliders"]),

            // Glutes
            e("Hip Thrust", .glutes, ["Barbell", "Bench"]),
            e("Machine Hip Thrust", .glutes, ["Hip Thrust Machine"]),
            e("Glute Bridge", .glutes, []),
            e("Single-Leg Glute Bridge", .glutes, []),
            e("Kettlebell Swing", .glutes, ["Kettlebell"]),
            e("Sumo Deadlift", .glutes, ["Barbell"]),
            e("Cable Kickback", .glutes, ["Cable Machine"]),
            e("Curtsy Lunge", .glutes, ["Dumbbells"]),
            e("Frog Pump", .glutes, []),
            e("Banded Lateral Walk", .glutes, ["Resistance Band"]),
            e("Fire Hydrant", .glutes, []),

            // Calves
            e("Standing Calf Raise", .calves, ["Calf Raise Machine"]),
            e("Seated Calf Raise", .calves, ["Calf Raise Machine"]),
            e("Smith Machine Calf Raise", .calves, ["Smith Machine"]),
            e("Single-Leg Calf Raise", .calves, []),
            e("Donkey Calf Raise", .calves, []),
            e("Calf Raise", .calves, ["Calf Raise Machine"]),

            // Core. The isometric holds are strength work (3-set blocks
            // stay), but take no heart-rate prescription; per-side and
            // positional holds start at an honest 30 s where the plank
            // keeps 45.
            e("Plank", .core, [], .duration, heartRate: false),
            e("Side Plank", .core, [], .duration, seconds: 30, heartRate: false),
            e("Dead Bug", .core, [], .duration, seconds: 30, heartRate: false),
            e("Bird Dog", .core, [], .duration, seconds: 30, heartRate: false),
            e("Hollow Hold", .core, [], .duration, seconds: 30, heartRate: false),
            e("Crunch", .core, []),
            e("Cable Crunch", .core, ["Cable Machine"]),
            e("Sit-Up", .core, []),
            e("Russian Twist", .core, ["Medicine Ball"]),
            e("Hanging Knee Raise", .core, ["Pull-Up Bar"]),
            e("Hanging Leg Raise", .core, ["Pull-Up Bar"]),
            e("Toes to Bar", .core, ["Pull-Up Bar"]),
            e("Ab Wheel Rollout", .core, ["Ab Wheel"]),
            e("Mountain Climber", .core, [], .duration, seconds: 30),
            e("Bicycle Crunch", .core, []),
            e("V-Up", .core, []),
            e("Leg Raise", .core, []),
            e("Pallof Press", .core, ["Cable Machine"]),
            e("Suitcase Carry", .core, ["Kettlebell"], .duration),
            e("Farmer's Carry", .core, ["Dumbbells"], .duration),
            e("Woodchopper", .core, ["Cable Machine"]),
            e("Medicine Ball Slam", .core, ["Medicine Ball"]),

            // Full Body
            e("Burpee", .fullBody, []),
            // Technical/max-effort movements: nobody's prescription is
            // the global 10-rep floor — cleans live at 3-5, a get-up
            // at 3 a side.
            e("Clean and Press", .fullBody, ["Barbell"], reps: 5),
            e("Power Clean", .fullBody, ["Barbell"], reps: 3),
            e("Kettlebell Clean and Press", .fullBody, ["Kettlebell"], reps: 5),
            e("Kettlebell Snatch", .fullBody, ["Kettlebell"]),
            e("Thruster", .fullBody, ["Barbell", "Squat Rack"]),
            e("Dumbbell Thruster", .fullBody, ["Dumbbells"]),
            e("Turkish Get-Up", .fullBody, ["Kettlebell"], reps: 3),
            e("Sled Push", .fullBody, ["Sled"], .duration),
            // Interval-shaped conditioning keeps 3 "rounds" but gets an
            // honest round length: battle ropes burn out in 30 s, a bag
            // round is boxing's 3 minutes, a jump-rope round a minute.
            e("Battle Rope Waves", .fullBody, ["Battle Ropes"], .duration, seconds: 30),
            e("Box Jump", .fullBody, ["Plyo Box"]),
            e("Jump Rope", .fullBody, ["Jump Rope"], .duration, seconds: 60),
            // Machine cardio defaults to ONE steady piece — 3 "sets" of
            // rowing is an interval prescription, which stays a
            // deliberate configuration (bump Sets, add a block rest).
            e("Rowing", .fullBody, ["Rowing Machine"], .duration, sets: 1),
            e("Assault Bike", .fullBody, ["Air Bike"], .duration, sets: 1),
            e("Stationary Bike", .fullBody, ["Stationary Bike"], .duration, sets: 1),
            e("Treadmill Run", .fullBody, ["Treadmill"], .duration, sets: 1),
            e("Sandbag Carry", .fullBody, ["Sandbag"], .duration),
            // Road cardio (flexible metrics): the road is not gear, but
            // running is training — these make distance intervals
            // (6×400 m) and steady pieces first-class. One steady piece
            // by default, like the machines. Cycling DOES require gear
            // (equipment audit, 2026-07-15: it read as "Bodyweight"):
            // the Bicycle, whose declared profile derives the same
            // [distance, duration, speed] the old explicit override
            // spelled out. Running/Walking stay genuinely equipment-free.
            e("Running", .fullBody, [], .duration,
              metrics: MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true), sets: 1),
            e("Walking", .fullBody, [], .duration,
              metrics: MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true), sets: 1),
            e("Cycling", .fullBody, ["Bicycle"], .duration, sets: 1),

            // #235: every equipment type gates at least one exercise —
            // the 60 types the #222 sweep added get their movements.
            // Specialty bars
            e("Safety Bar Squat", .quads, ["Safety Squat Bar", "Squat Rack"]),
            e("Safety Bar Good Morning", .hamstrings, ["Safety Squat Bar", "Squat Rack"]),
            e("Swiss Bar Bench Press", .chest, ["Swiss Bar", "Bench"]),
            e("Swiss Bar Overhead Press", .shoulders, ["Swiss Bar"]),
            e("Cambered Bar Squat", .quads, ["Cambered Squat Bar", "Squat Rack"]),
            e("Axle Deadlift", .back, ["Axle Bar"]),
            e("Axle Clean and Press", .fullBody, ["Axle Bar"], reps: 5),
            // Benches + stations
            e("Decline Bench Press", .chest, ["Barbell", "Decline Bench"]),
            e("Decline Sit-Up", .core, ["Decline Bench"]),
            e("GHD Raise", .hamstrings, ["Glute-Ham Developer"]),
            e("GHD Sit-Up", .core, ["Glute-Ham Developer"]),
            e("Reverse Hyperextension", .glutes, ["Reverse Hyper Machine"]),
            e("Nordic Bench Curl", .hamstrings, ["Nordic Bench"], reps: 5),
            e("Weighted Sissy Squat", .quads, ["Sissy Squat Bench", "Weight Plate"]),
            e("Captain's Chair Leg Raise", .core, ["Captain's Chair"]),
            // Plate-loaded machines
            e("T-Bar Row", .back, ["T-Bar Row Machine"]),
            e("Belt Squat", .quads, ["Belt Squat Machine"]),
            e("Pendulum Squat", .quads, ["Pendulum Squat Machine"]),
            e("Machine Pullover", .back, ["Pullover Machine"]),
            // Selectorized machines
            e("Hip Abduction", .glutes, ["Hip Abduction Machine"]),
            e("Hip Adduction", .quads, ["Hip Adduction Machine"]),
            e("Assisted Pull-Up", .back, ["Assisted Pull-Up Machine"]),
            e("Assisted Dip", .triceps, ["Assisted Pull-Up Machine"]),
            e("Machine Crunch", .core, ["Ab Crunch Machine"]),
            e("Torso Rotation", .core, ["Torso Rotation Machine"]),
            e("Machine Lateral Raise", .shoulders, ["Lateral Raise Machine"]),
            e("Machine Bicep Curl", .biceps, ["Bicep Curl Machine"]),
            e("Machine Tricep Extension", .triceps, ["Tricep Extension Machine"]),
            e("Machine Back Extension", .back, ["Low Back Extension Machine"]),
            e("Multi-Hip Kickback", .glutes, ["Multi-Hip Machine"]),
            e("Machine Glute Kickback", .glutes, ["Glute Kickback Machine"]),
            // Cardio — one steady piece, like the other machines. The
            // ones whose ONLY work metric is duration (no distance or
            // calories on the console profile) get an honest 10-minute
            // piece: without it the work-metric floor would stamp them
            // with an absurd 45 s "steady" piece. Distance/calorie
            // machines (Ski Erg, Rowing, the bikes) stay target-less —
            // the driver-hijack rule.
            e("Ski Erg", .fullBody, ["Ski Erg"], .duration, sets: 1),
            e("Elliptical", .fullBody, ["Elliptical"], .duration, sets: 1, seconds: 600),
            e("Stair Climber", .fullBody, ["Stair Climber"], .duration, sets: 1, seconds: 600),
            e("Vertical Climber", .fullBody, ["Vertical Climber"], .duration, sets: 1, seconds: 600),
            e("Upper Body Ergometer", .fullBody, ["Upper Body Ergometer"], .duration, sets: 1, seconds: 600),
            // Strongman
            e("Yoke Carry", .fullBody, ["Yoke"], .duration),
            e("Farmers Handle Carry", .fullBody, ["Farmers Walk Handles"], .duration),
            e("Log Clean and Press", .fullBody, ["Log Bar"], reps: 5),
            e("Atlas Stone Load", .fullBody, ["Atlas Stone"], reps: 5),
            e("Circus Dumbbell Press", .shoulders, ["Circus Dumbbell"]),
            e("Husafell Carry", .fullBody, ["Husafell Stone"], .duration),
            e("Tire Flip", .fullBody, ["Tire"]),
            e("Sledgehammer Slam", .fullBody, ["Sledgehammer", "Tire"]),
            // Gymnastics + calisthenics: an L-sit is measured in tens of
            // seconds, and a climb "rep" is a whole ascent.
            e("Parallette L-Sit", .core, ["Parallettes"], .duration, seconds: 20, heartRate: false),
            e("Parallette Push-Up", .chest, ["Parallettes"]),
            e("Rope Climb", .back, ["Climbing Rope"], reps: 3),
            e("Peg Board Ascent", .back, ["Peg Board"], reps: 3),
            e("Stall Bar Leg Raise", .core, ["Stall Bars"]),
            // Small equipment
            e("Slam Ball Slam", .fullBody, ["Slam Ball"]),
            e("Stability Ball Leg Curl", .hamstrings, ["Stability Ball"]),
            e("Stability Ball Rollout", .core, ["Stability Ball"]),
            e("Balance Trainer Squat", .quads, ["Balance Trainer"]),
            e("Slider Lunge", .quads, ["Sliders"]),
            e("Body Saw", .core, ["Sliders"], .duration, seconds: 30, heartRate: false),
            e("Chain Bench Press", .chest, ["Barbell", "Bench", "Weightlifting Chains"]),
            e("Weighted Dip", .chest, ["Dip Station", "Dip Belt"]),
            e("Weighted Pull-Up", .back, ["Pull-Up Bar", "Dip Belt"]),
            e("Weighted Push-Up", .chest, ["Weight Vest"]),
            e("Ruck", .fullBody, ["Weight Vest"], .duration,
              metrics: MetricProfile([.weight, .distance, .duration], distanceUnit: .miles), sets: 1),
            e("Mace 360", .shoulders, ["Macebell"]),
            e("Steel Club Mill", .shoulders, ["Steel Club"]),
            e("Bulgarian Bag Spin", .fullBody, ["Bulgarian Bag"]),
            // A roll-up is a full up-and-down trip — 3 torches forearms.
            e("Wrist Roller Roll-Up", .biceps, ["Wrist Roller"], reps: 3),
            e("Neck Harness Extension", .shoulders, ["Neck Harness"]),
            e("Gripper Close", .biceps, ["Hand Gripper"]),
            // A bag round is boxing's three minutes, not a 45 s hold.
            e("Heavy Bag Rounds", .fullBody, ["Heavy Bag"], .duration, seconds: 180),
            e("Agility Ladder Drills", .fullBody, ["Agility Ladder"], .duration),
            e("Tibialis Raise", .calves, ["Tibialis Bar"]),
            e("Slant Board Squat", .quads, ["Slant Board"]),

            // MARK: Stretches + mobility
            // Warmup and cooldown work, first-class (Dave, 2026-07-11:
            // "finish with stretching, sometimes at the start after a
            // warmup"). No new primitives: a static stretch is a timed
            // HOLD (.duration → .durationOnly, run as an auto-timer on the
            // set screen); a dynamic drill is rep-based (default type →
            // .repsOnly). Each carries its TARGET muscle so it lives in
            // the same equipment⇢exercise⇢routine graph and surfaces in
            // the library search — hip openers cluster under glutes, neck
            // rides shoulders and forearm/biceps under biceps, matching
            // how the catalog already files adduction/neck/grip work.
            // All bodyweight, so they reach everyone and add no gear.
            // Static holds (timed): the `stretch` shape — ONE 30 s hold,
            // no HR prescription (config audit, 2026-07-15). Repeats
            // stay one Sets-tap away.
            stretch("Standing Hamstring Stretch", .hamstrings),
            stretch("Standing Quad Stretch", .quads),
            stretch("Kneeling Hip Flexor Stretch", .quads),
            stretch("Figure-Four Stretch", .glutes),
            stretch("Pigeon Pose", .glutes),
            stretch("Butterfly Stretch", .glutes),
            stretch("Standing Calf Stretch", .calves),
            stretch("Downward Dog", .fullBody),
            stretch("Doorway Chest Stretch", .chest),
            stretch("Cross-Body Shoulder Stretch", .shoulders),
            stretch("Neck Stretch", .shoulders),
            stretch("Overhead Triceps Stretch", .triceps),
            stretch("Standing Biceps Stretch", .biceps),
            stretch("Child's Pose", .back),
            stretch("Seated Spinal Twist", .back),
            stretch("Lat Stretch", .back),
            stretch("Cobra Stretch", .core),
            stretch("Standing Side Bend Stretch", .core),
            // Dynamic warmup drills: the `mobility` shape — one pass of
            // reps through a warmup, not a 3-set block.
            mobility("Arm Circles", .shoulders),
            mobility("Leg Swings", .hamstrings),
            mobility("Hip Circles", .glutes),
            mobility("Walking Knee Hug", .glutes),
            mobility("Standing Torso Twist", .core),
            mobility("Cat-Cow", .back),
            mobility("World's Greatest Stretch", .fullBody),
            mobility("Inchworm", .fullBody),
        ]
    }()

    // MARK: - Equipment configuration (#236)

    /// Which built-ins are incrementally LOADABLE — plates, pins,
    /// bells, stacks, or a stepped rating that IS the load (bands and
    /// grippers are sold in lb ratings) — and therefore get a
    /// weight-step option. A bench holds you; a barbell holds plates.
    /// Custom equipment always shows the option (the user created it;
    /// we can't classify intent).
    static let loadableEquipmentNames: Set<String> = [
        "Barbell", "EZ Bar", "Trap Bar", "Safety Squat Bar", "Swiss Bar",
        "Cambered Squat Bar", "Axle Bar", "Log Bar", "Dumbbells",
        "Kettlebell", "Weight Plate", "Sandbag", "Circus Dumbbell",
        "Atlas Stone", "Husafell Stone", "Macebell", "Steel Club",
        "Bulgarian Bag", "Slam Ball", "Medicine Ball", "Weight Vest",
        "Dip Belt", "Weightlifting Chains", "Wrist Roller", "Neck Harness",
        "Landmine", "Sled", "Yoke", "Farmers Walk Handles", "Tibialis Bar",
        "Reverse Hyper Machine", "Resistance Band", "Hand Gripper",
        "Smith Machine", "Cable Machine", "Leg Press Machine",
        "Lat Pulldown Machine", "Leg Extension Machine", "Leg Curl Machine",
        "Calf Raise Machine", "Hack Squat Machine", "Hip Thrust Machine",
        "Pec Deck Machine", "Chest Press Machine", "Shoulder Press Machine",
        "Seated Row Machine", "T-Bar Row Machine", "Belt Squat Machine",
        "Pendulum Squat Machine", "Pullover Machine", "Hip Abduction Machine",
        "Hip Adduction Machine", "Assisted Pull-Up Machine",
        "Ab Crunch Machine", "Torso Rotation Machine", "Lateral Raise Machine",
        "Bicep Curl Machine", "Tricep Extension Machine",
        "Low Back Extension Machine", "Multi-Hip Machine",
        "Glute Kickback Machine",
    ]

    /// Whether the given equipment's detail screen offers weight-step
    /// configuration (#236: config adapts to the equipment). Custom gear
    /// with a declared exercise-config profile is loadable only when
    /// that profile tracks load — a custom spin bike whose exercises
    /// track duration/resistance has no plates to step. Undeclared
    /// customs keep the old always-loadable default (we can't classify
    /// the user's intent).
    static func isLoadable(_ equipment: Equipment) -> Bool {
        if equipment.isBuiltIn { return loadableEquipmentNames.contains(equipment.name) }
        guard let profile = equipment.suggestedProfile else { return true }
        return profile.tracksLoad
    }

    // MARK: - Metric profiles (flexible metrics)

    /// Suggested profiles for gear whose exercises track more than the
    /// classic weight×reps pair — cardio machines (the console's real
    /// dials), assisted machines (a stack that helps instead of loads),
    /// carry implements (load over ground), the plyo box (height). The
    /// evaluation that produced these lives in the feature's design
    /// notes; every entry answers "what does a lifter actually set and
    /// read on this thing".
    static let equipmentProfiles: [String: MetricProfile] = [
        // Ergs: pieces are distance-first (2000 m), splits per 500 m,
        // damper as the setting.
        "Rowing Machine": MetricProfile([.distance, .duration, .pace, .resistance]),
        "Ski Erg": MetricProfile([.distance, .duration, .pace, .resistance]),
        // The air bike prescribes in calories and punishes in watts.
        "Air Bike": MetricProfile([.duration, .calories, .power]),
        "Stationary Bike": MetricProfile([.duration, .distance, .resistance, .power], distanceUnit: .miles),
        "Bicycle": MetricProfile([.distance, .duration, .speed], distanceUnit: .miles),
        "Treadmill": MetricProfile([.distance, .duration, .speed, .incline], distanceUnit: .miles),
        "Elliptical": MetricProfile([.duration, .resistance, .incline]),
        "Stair Climber": MetricProfile([.duration, .resistance]),
        "Vertical Climber": MetricProfile([.duration]),
        "Upper Body Ergometer": MetricProfile([.duration, .resistance]),
        // The stack subtracts: less assistance IS the progression.
        "Assisted Pull-Up Machine": MetricProfile([.assistance, .reps]),
        "Plyo Box": MetricProfile([.height, .reps]),
        // Carries: load over ground — meters, like the strongman events.
        "Sled": MetricProfile([.weight, .distance, .duration]),
        "Yoke": MetricProfile([.weight, .distance, .duration]),
        "Farmers Walk Handles": MetricProfile([.weight, .distance, .duration]),
        "Husafell Stone": MetricProfile([.weight, .distance, .duration]),
        "Jump Rope": MetricProfile([.duration]),
        "Battle Ropes": MetricProfile([.duration]),
        "Heavy Bag": MetricProfile([.duration]),
        "Agility Ladder": MetricProfile([.duration]),
    ]

    static func equipmentProfile(named name: String) -> MetricProfile? {
        equipmentProfiles[name]
    }

    /// What a new exercise on this gear should track — the shared
    /// derivation for the built-in catalog AND the editor's prefill:
    /// union the gear's declared profiles, add weight when anything is
    /// loadable (unless assistance already speaks for the load), and
    /// guarantee a work metric from the legacy type when the union
    /// doesn't provide one.
    static func mergeSuggestedProfiles(_ matched: [MetricProfile], hasLoadable: Bool, type: ExerciseType) -> MetricProfile {
        guard !matched.isEmpty else {
            if type == .duration {
                return hasLoadable ? MetricProfile([.weight, .duration]) : .durationOnly
            }
            return hasLoadable ? .weightReps : .repsOnly
        }
        var metrics = matched.flatMap(\.metrics)
        let distanceUnit = matched.first {
            $0.metrics.contains(where: [.distance, .pace, .speed].contains)
        }?.distanceUnit ?? .meters
        if hasLoadable, !metrics.contains(.assistance) {
            metrics.append(.weight)
        }
        var profile = MetricProfile(metrics, distanceUnit: distanceUnit)
        if !profile.isValid {
            profile = MetricProfile(
                profile.metrics + [type == .duration ? .duration : .reps],
                distanceUnit: distanceUnit
            )
        }
        return profile
    }

    /// Table-backed derivation for built-in definitions (names only).
    static func suggestedProfile(type: ExerciseType, equipmentNames: [String]) -> MetricProfile {
        mergeSuggestedProfiles(
            equipmentNames.compactMap { equipmentProfiles[$0] },
            hasLoadable: equipmentNames.contains(where: loadableEquipmentNames.contains),
            type: type
        )
    }

    /// Live-model derivation for the editor's prefill — custom gear's
    /// declared profiles participate alongside the built-in table.
    static func suggestedProfile(type: ExerciseType, equipment: [Equipment]) -> MetricProfile {
        mergeSuggestedProfiles(
            equipment.compactMap(\.suggestedProfile),
            hasLoadable: equipment.contains(where: isLoadable),
            type: type
        )
    }

    /// The catalog's profile for a built-in exercise — the fallback
    /// `Exercise.metricProfile` resolves through when no per-store
    /// customization exists, so existing stores pick up rich profiles
    /// with zero migration writes.
    private static let builtInProfilesByName: [String: MetricProfile] = {
        Dictionary(uniqueKeysWithValues: builtInExerciseDefinitions.map { def in
            (def.name, def.metrics ?? suggestedProfile(type: def.exerciseType, equipmentNames: def.equipmentNames))
        })
    }()

    static func builtInProfile(named name: String) -> MetricProfile? {
        builtInProfilesByName[name]
    }

}

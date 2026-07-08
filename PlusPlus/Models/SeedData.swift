import Foundation
import SwiftData
import PlusPlusKit

enum SeedData {
    /// `populateLibrary: false` (#185) seeds built-in exercises OUT of
    /// the library: a fresh install's Exercises tab is empty, not a
    /// pre-curation chore — the catalog stays fully browsable and the
    /// optional populate step (or plain usage) grows the library.
    /// Equipment still seeds in-library; the setup step curates it.
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
            // Fresh stores own everything until the setup step curates;
            // a store that already curated ownership doesn't suddenly
            // "own" a hack squat machine because the catalog grew.
            item.inLibrary = isFreshStore
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
            // Catalog, not library (#185) — the populate offer or plain
            // usage grows the library. `populateLibrary` is the smoke
            // tests' shortcut and only meaningful on a fresh store.
            exercise.inLibrary = isFreshStore && populateLibrary
            context.insert(exercise)
            exercise.equipment = def.equipmentNames.compactMap { equipmentByName[$0.lowercased()] }
        }

        try? context.save()
    }

    /// What the populate offer would add — computed at ask time (#204),
    /// so a stale flag can never overstate.
    static func populateCandidateCount(context: ModelContext) -> Int {
        let exercises = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []
        return exercises.filter { exercise in
            !exercise.inLibrary
                && !exercise.equipment.contains { !$0.isDeleted && !$0.inLibrary }
        }.count
    }

    /// The optional population step (#185): everything the owned
    /// equipment supports joins the library. Returns the count added.
    @discardableResult
    static func populateLibraryFromEquipment(context: ModelContext) -> Int {
        let exercises = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []
        var added = 0
        for exercise in exercises where !exercise.inLibrary {
            let missing = exercise.equipment.contains { !$0.isDeleted && !$0.inLibrary }
            if !missing {
                exercise.inLibrary = true
                added += 1
            }
        }
        return added
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

    // MARK: - Equipment

    static var builtInEquipment: [Equipment] {
        [
            // Free weights + bars
            "Barbell", "EZ Bar", "Trap Bar", "Dumbbells", "Kettlebell",
            "Weight Plate", "Sandbag",
            // Racks, benches, stations
            "Squat Rack", "Bench", "Incline Bench", "Preacher Bench",
            "Dip Station", "Pull-Up Bar", "Back Extension Bench",
            "Plyo Box", "Landmine",
            // Machines
            "Smith Machine", "Cable Machine", "Leg Press Machine",
            "Lat Pulldown Machine", "Leg Extension Machine",
            "Leg Curl Machine", "Calf Raise Machine", "Hack Squat Machine",
            "Hip Thrust Machine", "Pec Deck Machine", "Chest Press Machine",
            "Shoulder Press Machine", "Seated Row Machine",
            // Conditioning + accessories
            "Rowing Machine", "Stationary Bike", "Treadmill", "Sled",
            "Battle Ropes", "Jump Rope", "Medicine Ball", "Ab Wheel",
            "Resistance Band", "Suspension Trainer", "Gymnastic Rings",
        ].map { Equipment(name: $0, isBuiltIn: true) }
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
    }

    static func builtInDefinition(named name: String) -> BuiltInExerciseDefinition? {
        builtInExerciseDefinitions.first { $0.name == name }
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
        func e(_ name: String, _ muscle: MuscleGroup, _ eqNames: [String], _ type: ExerciseType = .weightReps) -> BuiltInExerciseDefinition {
            BuiltInExerciseDefinition(name: name, muscleGroup: muscle, equipmentNames: eqNames, exerciseType: type)
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
            e("Landmine Row", .back, ["Landmine"]),
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
            e("Landmine Press", .shoulders, ["Landmine"]),
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
            e("Wall Sit", .quads, [], .duration),
            e("Sissy Squat", .quads, []),

            // Hamstrings
            e("Romanian Deadlift", .hamstrings, ["Barbell"]),
            e("Dumbbell Romanian Deadlift", .hamstrings, ["Dumbbells"]),
            e("Stiff-Leg Deadlift", .hamstrings, ["Barbell"]),
            e("Single-Leg Romanian Deadlift", .hamstrings, ["Dumbbells"]),
            e("Leg Curl", .hamstrings, ["Leg Curl Machine"]),
            e("Nordic Curl", .hamstrings, []),
            e("Glute-Ham Raise", .hamstrings, ["Back Extension Bench"]),
            e("Cable Pull-Through", .hamstrings, ["Cable Machine"]),
            e("Slider Leg Curl", .hamstrings, []),

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

            // Core
            e("Plank", .core, [], .duration),
            e("Side Plank", .core, [], .duration),
            e("Dead Bug", .core, [], .duration),
            e("Bird Dog", .core, [], .duration),
            e("Hollow Hold", .core, [], .duration),
            e("Crunch", .core, []),
            e("Cable Crunch", .core, ["Cable Machine"]),
            e("Sit-Up", .core, []),
            e("Russian Twist", .core, ["Medicine Ball"]),
            e("Hanging Knee Raise", .core, ["Pull-Up Bar"]),
            e("Hanging Leg Raise", .core, ["Pull-Up Bar"]),
            e("Toes to Bar", .core, ["Pull-Up Bar"]),
            e("Ab Wheel Rollout", .core, ["Ab Wheel"]),
            e("Mountain Climber", .core, [], .duration),
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
            e("Clean and Press", .fullBody, ["Barbell"]),
            e("Power Clean", .fullBody, ["Barbell"]),
            e("Kettlebell Clean and Press", .fullBody, ["Kettlebell"]),
            e("Kettlebell Snatch", .fullBody, ["Kettlebell"]),
            e("Thruster", .fullBody, ["Barbell", "Squat Rack"]),
            e("Dumbbell Thruster", .fullBody, ["Dumbbells"]),
            e("Turkish Get-Up", .fullBody, ["Kettlebell"]),
            e("Sled Push", .fullBody, ["Sled"], .duration),
            e("Battle Rope Waves", .fullBody, ["Battle Ropes"], .duration),
            e("Box Jump", .fullBody, ["Plyo Box"]),
            e("Jump Rope", .fullBody, ["Jump Rope"], .duration),
            e("Rowing", .fullBody, ["Rowing Machine"], .duration),
            e("Assault Bike", .fullBody, ["Stationary Bike"], .duration),
            e("Treadmill Run", .fullBody, ["Treadmill"], .duration),
            e("Sandbag Carry", .fullBody, ["Sandbag"], .duration),
        ]
    }()
}

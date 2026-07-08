import Foundation
import SwiftData
import PlusPlusKit

enum SeedData {
    /// `populateLibrary: false` (#185) seeds built-in exercises OUT of
    /// the library: a fresh install's Exercises tab is empty, not a
    /// pre-curation chore — the catalog stays fully browsable and the
    /// optional populate step (or plain usage) grows the library.
    /// Equipment still seeds in-library; the setup step curates it.
    static func loadIfNeeded(context: ModelContext, populateLibrary: Bool = false) {
        let predicate = #Predicate<Exercise> { $0.isBuiltIn == true }
        let descriptor = FetchDescriptor<Exercise>(predicate: predicate)
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let equipment = builtInEquipment
        for item in equipment {
            context.insert(item)
        }

        let exercises = makeBuiltInExercises(equipment: equipment)
        for exercise in exercises {
            exercise.inLibrary = populateLibrary
            context.insert(exercise)
        }

        try? context.save()
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
            "Barbell", "Squat Rack", "Bench", "Dumbbells",
            "Cable Machine", "Leg Press Machine", "Lat Pulldown Machine",
            "Leg Extension Machine", "Leg Curl Machine", "Calf Raise Machine",
            "Kettlebell", "Resistance Band", "Pull-Up Bar",
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
            e("Incline Dumbbell Press", .chest, ["Dumbbells", "Bench"]),
            e("Cable Fly", .chest, ["Cable Machine"]),
            e("Push-Up", .chest, []),

            // Back
            e("Barbell Row", .back, ["Barbell"]),
            e("Pull-Up", .back, ["Pull-Up Bar"]),
            e("Lat Pulldown", .back, ["Lat Pulldown Machine"]),
            e("Cable Row", .back, ["Cable Machine"]),

            // Shoulders
            e("Overhead Press", .shoulders, ["Barbell"]),
            e("Lateral Raise", .shoulders, ["Dumbbells"]),
            e("Face Pull", .shoulders, ["Cable Machine"]),

            // Biceps
            e("Barbell Curl", .biceps, ["Barbell"]),
            e("Dumbbell Curl", .biceps, ["Dumbbells"]),
            e("Hammer Curl", .biceps, ["Dumbbells"]),

            // Triceps
            e("Tricep Pushdown", .triceps, ["Cable Machine"]),
            e("Overhead Tricep Extension", .triceps, ["Dumbbells"]),

            // Quads
            e("Squat", .quads, ["Barbell", "Squat Rack"]),
            e("Leg Press", .quads, ["Leg Press Machine"]),
            e("Leg Extension", .quads, ["Leg Extension Machine"]),

            // Hamstrings
            e("Romanian Deadlift", .hamstrings, ["Barbell"]),
            e("Leg Curl", .hamstrings, ["Leg Curl Machine"]),

            // Glutes
            e("Hip Thrust", .glutes, ["Barbell", "Bench"]),
            e("Kettlebell Swing", .glutes, ["Kettlebell"]),

            // Calves
            e("Calf Raise", .calves, ["Calf Raise Machine"]),

            // Core
            e("Plank", .core, [], .duration),
            e("Dead Bug", .core, [], .duration),

            // Full Body
            e("Burpee", .fullBody, []),
        ]
    }()
}

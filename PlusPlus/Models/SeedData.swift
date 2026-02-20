import Foundation
import SwiftData

enum SeedData {
    static func loadIfNeeded(context: ModelContext) {
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
            context.insert(exercise)
        }

        try? context.save()
    }

    // MARK: - Equipment

    static var builtInEquipment: [Equipment] {
        [
            "Barbell", "Squat Rack", "Bench", "Dumbbells",
            "Cable Machine", "Leg Press Machine", "Lat Pulldown Machine",
            "Leg Extension Machine", "Leg Curl Machine", "Calf Raise Machine",
            "Kettlebell", "Resistance Band",
        ].map { Equipment(name: $0, isBuiltIn: true) }
    }

    // MARK: - Exercises

    private static func makeBuiltInExercises(equipment: [Equipment]) -> [Exercise] {
        let eq = Dictionary(uniqueKeysWithValues: equipment.map { ($0.name, $0) })

        func e(_ name: String, _ muscle: MuscleGroup, _ eqNames: [String], _ type: ExerciseType = .weightReps) -> Exercise {
            Exercise(
                name: name,
                muscleGroup: muscle,
                equipment: eqNames.compactMap { eq[$0] },
                exerciseType: type,
                isBuiltIn: true
            )
        }

        return [
            // Chest
            e("Bench Press", .chest, ["Barbell", "Bench"]),
            e("Incline Dumbbell Press", .chest, ["Dumbbells", "Bench"]),
            e("Cable Fly", .chest, ["Cable Machine"]),
            e("Push-Up", .chest, []),

            // Back
            e("Barbell Row", .back, ["Barbell"]),
            e("Pull-Up", .back, []),
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
        ]
    }
}

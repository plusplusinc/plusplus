#if DEBUG
import Foundation
import WorkoutStore

extension LaunchOptions {
    /// `-seedWorkouts YES`, with `resetsStore`: eight saved workouts of different shapes, as the
    /// Workouts list's drawing has them (a legs day, a pressing day, a short circuit, a stretch
    /// with no equipment, and a long full-body day), three more so Dumbbells alone leaves some
    /// one piece short (an upper-body day short a bench, a legs day short a kettlebell, and a
    /// balance day short a balance board, the longest piece's name), and one finished just
    /// after, so the app launches on the Workouts list.
    static var seedsWorkouts: Bool {
        UserDefaults.standard.bool(forKey: "seedWorkouts")
    }

    static func seedWorkouts(_ store: Store, weightUnit: WeightUnit) async throws {
        let now = Date.now
        var last: Workout?
        for (name, rows) in Self.seededWorkouts {
            let workout = Workout(name: name, exercises: rows.compactMap { id, sets in
                guard let exercise = Exercise.builtIn(id: id) else { return nil }
                var row = WorkoutExercise(exercise: exercise, weightUnit: weightUnit)
                row.plan.sets = sets
                return row
            })
            try await store.save(workout, at: now)
            last = workout
        }
        guard let last else { return }
        var finished = WorkoutSession(
            workoutID: last.id,
            workoutName: last.name,
            startedAt: now.addingTimeInterval(1),
        )
        finished.endedAt = now.addingTimeInterval(2)
        try await store.save(finished)
    }

    private static let seededWorkouts: [(String, [(String, Int)])] = [
        ("Full body", [
            ("barbell-bench-press", 5), ("barbell-row", 5), ("barbell-back-squat", 5),
            ("barbell-deadlift", 4), ("overhead-press", 4), ("biceps-curl", 4),
        ]),
        ("Morning stretch", [
            ("hamstring-stretch", 2), ("pigeon-stretch", 2), ("cat-cow", 2), ("childs-pose", 2),
        ]),
        ("Kettlebell circuit", [("kettlebell-swing", 3), ("burpee", 2), ("mountain-climber", 2)]),
        ("Push day", [
            ("barbell-bench-press", 5), ("incline-dumbbell-press", 4), ("overhead-press", 4),
            ("triceps-extension", 3),
        ]),
        ("Legs and back", [
            ("romanian-deadlift", 5), ("reverse-lunge", 4), ("step-up", 3), ("dumbbell-row", 3),
        ]),
        ("Upper body", [
            ("dumbbell-bench-press", 4), ("dumbbell-row", 4), ("lateral-raise", 3),
            ("biceps-curl", 3),
        ]),
        ("Legs", [("goblet-squat", 4), ("walking-lunge", 3), ("calf-raise", 3)]),
        ("Balance and calves", [("calf-raise", 3), ("balance-board-hold", 3)]),
    ]
}
#endif

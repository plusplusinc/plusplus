import Foundation
import SwiftData

@Model
final class ExerciseGroup {
    var routine: Routine?
    var order: Int
    var sets: Int
    /// Per-block rest override in seconds; nil rides the routine's
    /// restSeconds. This is what interval blocks need — 2-minute rests
    /// between 500 m rows while the workout default stays 90 s. (Amends
    /// the "per-workout rest only" decision: intervals are the proof it
    /// was deferred against.)
    var restSecondsOverride: Int?
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.group)
    var exercises: [RoutineExercise] = []

    init(order: Int = 0, sets: Int = 3) {
        self.order = order
        self.sets = sets
    }

    var sortedExercises: [RoutineExercise] {
        exercises.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var isSuperset: Bool {
        exercises.count > 1
    }

    func reindexExercises() {
        for (index, exercise) in sortedExercises.filter({ !$0.isDeleted }).enumerated() {
            exercise.order = index
        }
    }
}

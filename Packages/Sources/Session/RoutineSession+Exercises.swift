import Foundation
import OSLog
import WorkoutStore

extension RoutineSession {
    /// Adds a created exercise to the list at once, and returns it once it is stored, so a
    /// routine save that names it always lands after it: await this before adding its row.
    /// A failed save is logged, and the exercise stays usable this session.
    public func create(_ created: CreatedExercise) async -> Exercise {
        exercises = exercises.adding(created)
        do {
            try await store?.save(created)
        } catch {
            Logger.session.error("The created exercise didn't save: \(error)")
        }
        return Exercise(created: created)
    }

    /// Saves a created exercise's new settings. Every routine's rows of it read them at once,
    /// keeping their sets, reps or time, and weight; an automatic rest follows its new groups.
    public func customize(_ created: CreatedExercise, weightUnit: WeightUnit) async {
        exercises = exercises.adding(created)
        await changeExercises(weightUnit: weightUnit) { try await $0.save(created) }
    }

    /// Deletes a created exercise, and its rows from every routine that uses it.
    public func deleteExercise(_ id: Exercise.ID, weightUnit: WeightUnit) async {
        exercises = exercises.removing(id)
        await changeExercises(weightUnit: weightUnit) { try await $0.deleteExercise(id) }
    }

    /// The routines with a row of `id`, the latest opened or edited first.
    public func routines(using id: Exercise.ID) -> [Routine] {
        recent.filter { routine in routine.exercises.contains { $0.exercise.id == id } }
    }
}

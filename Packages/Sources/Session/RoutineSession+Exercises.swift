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

    /// Saves an exercise's new settings: a created one's own, a built-in's as its customization,
    /// stored apart from the catalog. Every routine's rows of it read them at once, keeping
    /// their sets, reps or time, and weight. A created exercise's automatic rest follows its new
    /// groups; a built-in's stays by its kind of lift.
    public func customize(
        _ id: Exercise.ID,
        to settings: ExerciseSettings,
        weightUnit: WeightUnit,
    ) async {
        let created = exercises.created(id: id).map { created in
            var created = created
            created.settings = settings
            return created
        }
        let shipped = exercises.original(id: id)
        await changeExercises(
            weightUnit: weightUnit,
            storing: { store in
                if let created {
                    try await store.save(created)
                } else if let shipped {
                    try await store.save(Customization(of: shipped, to: settings))
                }
            },
            listing: { $0.customizing(id, to: settings) },
        )
    }

    /// Puts the built-in `id` back as it shipped, in every routine that uses it; the rows keep
    /// their numbers.
    public func clearCustomizations(_ id: Exercise.ID, weightUnit: WeightUnit) async {
        await changeExercises(
            weightUnit: weightUnit,
            storing: { try await $0.clearCustomizations(id) },
            listing: { $0.clearingCustomizations(id) },
        )
    }

    /// Deletes a created exercise, and its rows from every routine that uses it.
    public func deleteExercise(_ id: Exercise.ID, weightUnit: WeightUnit) async {
        await changeExercises(
            weightUnit: weightUnit,
            storing: { try await $0.deleteExercise(id) },
            listing: { $0.removing(id) },
        )
    }

    /// Whether the open routine has a row of `id`: the routine a delete's question names first.
    public func openRoutineUses(_ id: Exercise.ID) -> Bool {
        current.exercises.contains { $0.exercise.id == id }
    }

    /// The routines with a row of `id`, the latest opened or edited first.
    public func routines(using id: Exercise.ID) -> [Routine] {
        recent.filter { routine in routine.exercises.contains { $0.exercise.id == id } }
    }
}

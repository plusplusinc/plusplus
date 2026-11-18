import Session
import SwiftUI
import WorkoutStore

/// An exercise's Customize form (`ExerciseForm`) wired to the session, as Exercises and Add
/// exercise push it. A created exercise's: each change stored as made, and Delete removing the
/// exercise and its rows, then going `back`. A built-in's: each change stored as made, apart from
/// the catalog, and Clear customizations putting it back as it shipped. Nothing shows for an id
/// the list no longer has.
struct CustomizeScreen: View {
    let id: Exercise.ID
    let session: RoutineSession
    let namer: RoutineNamer
    /// Runs once each change or the delete has reached the store.
    var onStored: () -> Void = { }
    let back: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let weightUnit = WeightUnit(region: locale)
        let usedIn = session.routines(using: id).map(namer.listedName(of:))
        if let exercise = session.exercises.exercise(id: id) {
            ExerciseForm(
                customizing: id,
                settings: exercise.settings,
                exercises: session.exercises,
                usedIn: usedIn,
                onSave: { settings in
                    await session.customize(id, to: settings, weightUnit: weightUnit)
                    onStored()
                },
                ending: ending(weightUnit: weightUnit),
            )
        }
    }

    /// Delete for a created exercise; Clear customizations for a built-in, back to how it
    /// shipped.
    private func ending(weightUnit: WeightUnit) -> ExerciseForm.Ending {
        if let original = session.exercises.original(id: id) {
            .clear(original: original.settings) {
                await session.clearCustomizations(id, weightUnit: weightUnit)
                onStored()
            }
        } else {
            .delete {
                await session.deleteExercise(id, weightUnit: weightUnit)
                onStored()
                back()
            }
        }
    }
}

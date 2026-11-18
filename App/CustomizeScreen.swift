import Session
import SwiftUI
import WorkoutStore

/// An exercise's Customize form (`ExerciseForm`) wired to the session, as Exercises and Add
/// exercise push it. A created exercise's: each change stored as made, and Delete removing the
/// exercise and its rows, then going `back`. A built-in's: its settings as it shipped, ending in
/// Clear customizations. Nothing shows for an id the list no longer has.
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
        if let created = session.exercises.created(id: id) {
            ExerciseForm(
                customizing: id,
                settings: created.settings,
                exercises: session.exercises,
                usedIn: usedIn,
                onSave: { settings in
                    var changed = created
                    changed.settings = settings
                    await session.customize(changed, weightUnit: weightUnit)
                    onStored()
                },
                ending: .delete {
                    await session.deleteExercise(id, weightUnit: weightUnit)
                    onStored()
                    back()
                },
            )
        } else if let builtIn = session.exercises.exercise(id: id) {
            ExerciseForm(
                customizing: id,
                settings: builtIn.settings,
                exercises: session.exercises,
                usedIn: usedIn,
                onSave: { _ in },
                ending: .clear(original: builtIn.settings),
            )
        }
    }
}

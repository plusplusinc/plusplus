import Session
import SwiftUI
import WorkoutStore

/// A created exercise's Customize form (`ExerciseForm`) wired to the session, as Exercises and
/// Add exercise push it: each change stored as made, and Delete removing the exercise and its
/// rows, then going `back`. Nothing shows for an id the list no longer has.
struct CustomizeScreen: View {
    let id: Exercise.ID
    let session: RoutineSession
    let namer: RoutineNamer
    /// Runs once each change or the delete has reached the store.
    var onStored: () -> Void = { }
    let back: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        if let created = session.exercises.created(id: id) {
            let weightUnit = WeightUnit(region: locale)
            ExerciseForm(
                customizing: created,
                exercises: session.exercises,
                usedIn: session.routines(using: id).map(namer.listedName(of:)),
                onSave: {
                    await session.customize($0, weightUnit: weightUnit)
                    onStored()
                },
                onDelete: {
                    await session.deleteExercise(id, weightUnit: weightUnit)
                    onStored()
                    back()
                },
            )
        }
    }
}

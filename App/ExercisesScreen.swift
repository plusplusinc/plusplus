import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Exercises, pushed from the drawer onto the screen that showed, with Back: the exercise list
/// (`ExerciseListView`) under a large title. Create stores the new exercise and comes back to
/// the list, where it shows. A tap on an exercise someone created pushes its Customize form
/// (`ExerciseForm`); Save and Delete come back to the list once the routines show the change.
/// A built-in's row opens nothing yet.
struct ExercisesScreen: View {
    let session: RoutineSession
    let namer: RoutineNamer

    /// The id of the exercise whose form shows.
    @State private var customizing: Exercise.ID?
    @Environment(\.locale) private var locale

    var body: some View {
        ExerciseListView(
            exercises: session.exercises,
            onTap: { customizing = $0.id },
            isTappable: { session.exercises.created(id: $0.id) != nil },
            returnsAfterCreate: true,
            onCreate: { _ = await session.create($0) },
        )
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $customizing) { id in
            if let created = session.exercises.created(id: id) {
                ExerciseForm(
                    customizing: created,
                    exercises: session.exercises,
                    usedIn: session.routines(using: id).map(namer.listedName(of:)),
                    onSave: { edited in
                        await session.customize(edited, weightUnit: weightUnit)
                        customizing = nil
                    },
                    onDelete: {
                        await session.deleteExercise(id, weightUnit: weightUnit)
                        customizing = nil
                    },
                )
            }
        }
        // The routines the forms count, as stored now.
        .task { await session.refreshRecent(weightUnit: weightUnit) }
    }

    private var weightUnit: WeightUnit {
        WeightUnit(region: locale)
    }
}

extension View {
    /// Pushes Exercises while the session shows it; the back button and swipe pop it.
    func exercisesDestination(_ session: RoutineSession, namer: RoutineNamer) -> some View {
        navigationDestination(
            isPresented: Binding {
                session.isExercisesShown
            } set: { isShown in
                if !isShown {
                    session.popExercises()
                }
            },
        ) {
            ExercisesScreen(session: session, namer: namer)
        }
    }
}

#Preview {
    NavigationStack {
        ExercisesScreen(
            session: RoutineSession(routine: Routine(), store: nil, namer: .muscleGroupsOnly),
            namer: .muscleGroupsOnly,
        )
    }
}

import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Exercises, pushed from the drawer onto the screen that showed, with Back: the exercise list
/// (`ExerciseListView`) under a large title. Create stores the new exercise and comes back to
/// the list, where it shows. A tap on a row opens nothing yet.
struct ExercisesScreen: View {
    let session: RoutineSession

    var body: some View {
        ExerciseListView(exercises: session.exercises, onTap: nil, returnsAfterCreate: true) {
            _ = await session.create($0)
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.large)
    }
}

extension View {
    /// Pushes Exercises while the session shows it; the back button and swipe pop it.
    func exercisesDestination(_ session: RoutineSession) -> some View {
        navigationDestination(
            isPresented: Binding {
                session.isExercisesShown
            } set: { isShown in
                if !isShown {
                    session.popExercises()
                }
            },
        ) {
            ExercisesScreen(session: session)
        }
    }
}

#Preview {
    NavigationStack {
        ExercisesScreen(
            session: RoutineSession(routine: Routine(), store: nil, namer: .muscleGroupsOnly),
        )
    }
}

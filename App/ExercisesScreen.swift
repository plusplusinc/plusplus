import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Exercises, a screen at the root as Routines is, shown from the drawer in place of the screen
/// that showed, with ++ leading its bar: the exercise list (`ExerciseListView`) under a large
/// title, with search as a round button at the bar's top trailing edge that opens into a field
/// across the bar, ++ turning into the field as it opens and back as it closes (`BarSearchField`).
/// While the field is open, ++ is gone; the edge swipe still opens the drawer.
/// Create stores the new exercise and comes back to the
/// list, where it shows. A tap on an exercise someone created pushes its Customize form
/// (`ExerciseForm`), with Back to the list; Save and Delete come back to the list once the
/// routines show the change. A built-in's row opens nothing yet.
struct ExercisesScreen: View {
    let session: RoutineSession
    let namer: RoutineNamer
    /// The id of the exercise whose form shows, held above the screen so the drawer's edge
    /// swipe stays off while the form takes it as Back.
    @Binding var customizing: Exercise.ID?

    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ExerciseListView(
                exercises: session.exercises,
                onTap: { customizing = $0.id },
                isTappable: { session.exercises.created(id: $0.id) != nil },
                returnsAfterCreate: true,
                // In the search's own bar item, not one of its own, so the search's field can
                // slide over it.
                barLeading: MenuButton(session: session, drawsGlass: true),
                onCreate: { _ = await session.create($0) },
            )
            .accessibilityHidden(session.isDrawerOpen)
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $customizing) { id in
                if let created = session.exercises.created(id: id) {
                    ExerciseForm(
                        customizing: created,
                        exercises: session.exercises,
                        usedIn: session.routines(using: id).map(namer.listedName(of:)),
                        onSave: { await session.customize($0, weightUnit: weightUnit) },
                        onDelete: {
                            await session.deleteExercise(id, weightUnit: weightUnit)
                            customizing = nil
                        },
                    )
                }
            }
        }
        // The routines the forms count, as stored now.
        .task { await session.refreshRecent(weightUnit: weightUnit) }
    }

    private var weightUnit: WeightUnit {
        WeightUnit(region: locale)
    }
}

#Preview {
    @Previewable @State var customizing: Exercise.ID?
    ExercisesScreen(
        session: RoutineSession(routine: Routine(), store: nil, namer: .muscleGroupsOnly),
        namer: .muscleGroupsOnly,
        customizing: $customizing,
    )
}

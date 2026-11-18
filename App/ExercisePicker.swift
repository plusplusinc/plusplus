import DesignSystem
import SwiftUI
import WorkoutStore

/// The sheet Add exercise opens: the exercise list (`ExerciseListView`) on a stack of its own,
/// with Close. Picking one hands it back; the presenter closes the sheet. Its inline title and
/// Close are drawn by the bar's search: Close turns into its field as it opens, which covers the
/// title, and back as it closes. Opening search takes the sheet to full height, as the system's
/// search does, whether or not a software keyboard comes up to push it. A swipe down closes the
/// sheet at any time.
///
/// Create stores the exercise and adds its row to the routine, as a pick does, but keeps the
/// sheet up and pushes the exercise's Customize form inside it, with Done in the bar's trailing
/// spot to close the sheet and the back chevron to the list.
struct ExercisePicker<Customize: View>: View {
    let exercises: ExerciseList
    let onPick: (Exercise) -> Void
    /// Runs as search opens, in the field's own transaction (`ExerciseListView.onSearchOpen`).
    var onSearchOpen: () -> Void = { }
    /// Stores the exercise and adds its row, returning it as stored.
    let onCreate: (CreatedExercise) async -> Exercise
    /// The Customize form for an exercise just created; its closure goes back to the list.
    @ViewBuilder let customize: (Exercise.ID, _ back: @escaping () -> Void) -> Customize

    @State private var customizing: Exercise.ID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            ExerciseListView(
                exercises: exercises,
                onTap: onPick,
                barTitle: "Add exercise",
                barLeading: closeButton,
                onSearchOpen: onSearchOpen,
                onCreate: { customizing = await onCreate($0).id },
            )
            // Still the screen's title for VoiceOver; the bar shows the search's drawn copy.
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $customizing) { id in
                customize(id) { customizing = nil }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            // The picker's own dismiss, which closes the sheet, not the push.
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }

    /// The system's Close in its glass circle, as the bar draws it, in the label's own primary
    /// white, not the search button's cream.
    private var closeButton: some View {
        Button(role: .close) {
            dismiss()
        } label: {
            Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.ppBarGlyph)
                // The bar sets the X a pixel left of the circle's middle and a pixel lower;
                // centered here, it sat that pixel off from the bar's own Close.
                .offset(x: -1 / displayScale, y: 1 / displayScale)
        }
        .buttonStyle(.barGlass(width: 0))
    }
}

#Preview {
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: {
        Exercise(created: $0)
    } customize: { _, _ in
        EmptyView()
    }
}

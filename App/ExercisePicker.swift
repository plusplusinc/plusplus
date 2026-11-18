import DesignSystem
import SwiftUI
import WorkoutStore

/// The sheet Add exercise opens: the exercise list (`ExerciseListView`) on a stack of its own,
/// with Close. Picking one hands it back; the presenter closes the sheet. Its inline title and
/// Close are drawn by the bar's search: its field takes Close in as it opens, covering the title,
/// and gives it back as it closes. Opening search takes the sheet to full height, as the system's
/// search does, whether or not a software keyboard comes up to push it. A swipe down closes the
/// sheet at any time.
struct ExercisePicker: View {
    let exercises: ExerciseList
    let onPick: (Exercise) -> Void
    /// Runs as search opens, in the field's own transaction (`ExerciseListView.onSearchOpen`).
    var onSearchOpen: () -> Void = { }
    /// Stores the exercise and adds its row; the presenter closes the sheet.
    let onCreate: (CreatedExercise) async -> Void

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
                onCreate: onCreate,
            )
            // Still the screen's title for VoiceOver; the bar shows the search's drawn copy.
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
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
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: { _ in }
}

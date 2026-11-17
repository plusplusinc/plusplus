import DesignSystem
import SwiftUI
import WorkoutStore

/// The sheet Add exercise opens: the exercise list (`ExerciseListView`) on a stack of its own,
/// with Close. Picking one hands it back; the presenter closes the sheet. Its inline title and
/// Close are drawn by the bar's search, whose field covers both as it opens and reveals them as
/// it closes; while covered, Close takes no taps. A swipe down closes the sheet at any time.
struct ExercisePicker: View {
    let exercises: ExerciseList
    let onPick: (Exercise) -> Void
    /// Stores the exercise and adds its row; the presenter closes the sheet.
    let onCreate: (CreatedExercise) async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseListView(
                exercises: exercises,
                onTap: onPick,
                searchesInBar: true,
                barTitle: "Add exercise",
                // In the search's own bar item, not one of its own: the bar lays separate items
                // out at once, so the field could not slide over Close along its motion.
                onBarClose: { dismiss() },
                onCreate: onCreate,
            )
            // Still the screen's title for VoiceOver; the bar shows the search's drawn copy.
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: { _ in }
}

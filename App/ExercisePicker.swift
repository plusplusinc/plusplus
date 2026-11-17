import DesignSystem
import SwiftUI
import WorkoutStore

/// The sheet Add exercise opens: the exercise list (`ExerciseListView`) on a stack of its own,
/// with Close. Picking one hands it back; the presenter closes the sheet.
struct ExercisePicker: View {
    let exercises: ExerciseList
    let onPick: (Exercise) -> Void
    /// Stores the exercise and adds its row; the presenter closes the sheet.
    let onCreate: (CreatedExercise) async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseListView(exercises: exercises, onTap: onPick, onCreate: onCreate)
                .navigationTitle("Add exercise")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: { _ in }
}

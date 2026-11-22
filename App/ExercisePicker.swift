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
/// Create stores the exercise and hands it to the presenter, which closes the sheet and adds
/// its row as a pick does.
///
/// Holding a row opens the system's context menu (`HoldMenu`): Customize… pushes that exercise's
/// Customize form inside the sheet, for any exercise, and back finds the list as it was; then,
/// red, Delete for one someone created, asking first in a centered alert with the form's own
/// question (`DeleteQuestion`). Confirmed, the row leaves the list as the rows below close the
/// gap, its letter heading with it if it was the letter's last; then, after a rest, its rows
/// leave the workout behind the sheet (`WorkoutScreen.deleteExercise(_:closing:)`).
struct ExercisePicker<Customize: View>: View {
    let exercises: ExerciseList
    let onPick: (Exercise) -> Void
    /// Runs as search opens or a filter's button is tapped, in the tap's own transaction
    /// (`ExerciseListView.onExpand`).
    var onExpand: () -> Void = { }
    /// Stores the exercise, closes the sheet, and adds its row; the flag says whether it still
    /// needs its name.
    let onCreate: (CreatedExercise, _ needsName: Bool) async -> Void
    /// Delete's question for the exercise, below its title (`DeleteQuestion`).
    let deleteMessage: (Exercise.ID) -> String
    /// Deletes the created exercise and its rows, from the confirming tap, showing its row
    /// leave the list (`WorkoutScreen.deleteExercise(_:closing:)`).
    let onDelete: (Exercise.ID) async -> Void
    /// The exercise's Customize form; its closure goes back to the list.
    @ViewBuilder let customize: (Exercise.ID, _ back: @escaping () -> Void) -> Customize

    /// The exercise whose Customize form is pushed.
    @State private var customizing: Exercise.ID?
    /// The created exercise Delete in the hold menu is asking about.
    @State private var deleting: Exercise?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            ExerciseListView(
                exercises: exercises,
                onTap: onPick,
                rowActions: holdMenu,
                barTitle: "Add exercise",
                barLeading: closeButton,
                onExpand: onExpand,
                onCreate: onCreate,
            )
            // Still the screen's title for VoiceOver; the bar shows the search's drawn copy.
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $customizing) { id in
                customize(id) { customizing = nil }
            }
        }
        // Here, not on the row: under the list's green tint the alert's Cancel came out green,
        // where the form's is white.
        .alert(
            "Delete \(deleting?.name ?? "")?",
            isPresented: Binding { deleting != nil } set: {
                if !$0 {
                    deleting = nil
                }
            },
            presenting: deleting,
        ) { exercise in
            Button("Cancel", role: .cancel) { }
            Button("Delete exercise", role: .destructive) {
                Task { await onDelete(exercise.id) }
            }
        } message: { exercise in
            Text(deleteMessage(exercise.id))
        }
    }

    private func holdMenu(_ exercise: Exercise) -> HoldMenu {
        HoldMenu(
            isCreated: exercises.original(id: exercise.id) == nil,
            onCustomize: { customizing = exercise.id },
            onDelete: { deleting = exercise },
        )
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

/// A row's hold menu in Add exercise, the system's context menu: Customize… for any exercise,
/// then, for one someone created, Delete, whose question the picker asks.
private struct HoldMenu: ViewModifier {
    let isCreated: Bool
    let onCustomize: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                menuItems
                    // The system's colors, not the list's green, which turned Delete's trash
                    // green beside its red title.
                    .tint(nil)
            }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Customize…", systemImage: "slider.horizontal.3", action: onCustomize)
        if isCreated {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .accessibilityIdentifier("picker.menu.delete")
        }
    }
}

#Preview {
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: { _, _ in
    } deleteMessage: { _ in
        ""
    } onDelete: { _ in
    } customize: { _, _ in
        EmptyView()
    }
}

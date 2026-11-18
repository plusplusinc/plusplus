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
///
/// Holding a row opens the system's context menu (`HoldMenu`): Customize… pushes that form the
/// same way, for any exercise, and back finds the list as it was; then, red, Delete for one
/// someone created, or Clear customizations for a built-in that has any, each asking first with
/// the form's own question.
struct ExercisePicker<Customize: View>: View {
    let exercises: ExerciseList
    let onPick: (Exercise) -> Void
    /// Runs as search opens, in the field's own transaction (`ExerciseListView.onSearchOpen`).
    var onSearchOpen: () -> Void = { }
    /// Stores the exercise and adds its row, returning it as stored.
    let onCreate: (CreatedExercise) async -> Exercise
    /// How many routines use the exercise, for Delete's question.
    let routineCount: (Exercise.ID) -> Int
    /// Deletes the created exercise and its rows.
    let onDelete: (Exercise.ID) async -> Void
    /// Puts the built-in back as it shipped.
    let onClear: (Exercise.ID) async -> Void
    /// The exercise's Customize form; its closure goes back to the list.
    @ViewBuilder let customize: (Exercise.ID, _ back: @escaping () -> Void) -> Customize

    @State private var customizing: Exercise.ID?
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

    private func holdMenu(_ exercise: Exercise) -> HoldMenu {
        let id = exercise.id
        return HoldMenu(
            exercise: exercise,
            original: exercises.original(id: id),
            isCustomized: exercises.customization(id: id) != nil,
            routineCount: { routineCount(id) },
            onCustomize: { customizing = id },
            onDelete: { await onDelete(id) },
            onClear: { await onClear(id) },
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

/// A row's hold menu in Add exercise, the system's context menu. The questions come out of the
/// row, as the form's come out of its buttons.
private struct HoldMenu: ViewModifier {
    let exercise: Exercise
    /// The built-in as it shipped; nil for one someone created.
    let original: Exercise?
    let isCustomized: Bool
    /// Read as Delete asks, not for every row the list draws.
    let routineCount: () -> Int
    let onCustomize: () -> Void
    let onDelete: () async -> Void
    let onClear: () async -> Void

    @State private var isAskingToDelete = false
    @State private var isAskingToClear = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                menuItems
                    // The system's colors, not the list's green, which turned Delete's trash
                    // green beside its red title.
                    .tint(nil)
            }
            .confirmationDialog(
                "Delete \(exercise.name)?",
                isPresented: $isAskingToDelete,
                titleVisibility: .visible,
            ) {
                Button("Delete exercise", role: .destructive) {
                    Task { await onDelete() }
                }
            } message: {
                Text(ExerciseForm.deleteMessage(routineCount: routineCount()))
            }
            .confirmationDialog(
                "Clear your customizations to \(original?.name ?? exercise.name)?",
                isPresented: $isAskingToClear,
                titleVisibility: .visible,
            ) {
                Button("Clear customizations", role: .destructive) {
                    Task { await onClear() }
                }
            } message: {
                if let original {
                    Text(ExerciseForm.clearMessage(exercise.settings, from: original.settings))
                }
            }
    }

    /// Customize… for any exercise; then Delete for a created one, or Clear customizations for
    /// a built-in that has any.
    @ViewBuilder
    private var menuItems: some View {
        Button("Customize…", systemImage: "slider.horizontal.3", action: onCustomize)
        if original == nil {
            Button("Delete", systemImage: "trash", role: .destructive) {
                isAskingToDelete = true
            }
            .accessibilityIdentifier("picker.menu.delete")
        } else if isCustomized {
            Button(
                "Clear customizations",
                systemImage: "arrow.uturn.backward",
                role: .destructive,
            ) {
                isAskingToClear = true
            }
            .accessibilityIdentifier("picker.menu.clear")
        }
    }
}

#Preview {
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: {
        Exercise(created: $0)
    } routineCount: { _ in
        0
    } onDelete: { _ in
    } onClear: { _ in
    } customize: { _, _ in
        EmptyView()
    }
}

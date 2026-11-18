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
/// sheet up: the presenter sets `path` to the row's values with the exercise's Customize form on
/// top, so the sheet becomes the new row's own sheet, its back chevron to the values.
///
/// Holding a row opens the system's context menu (`HoldMenu`): Customize… pushes that form, for
/// any exercise, and back finds the list as it was; then, red, Delete for one someone created,
/// asking first in a centered alert with the form's own question.
struct ExercisePicker<Customize: View, Values: View>: View {
    let exercises: ExerciseList
    /// The pages pushed over the list.
    @Binding var path: [PickerPage]
    let onPick: (Exercise) -> Void
    /// Runs as search opens, in the field's own transaction (`ExerciseListView.onSearchOpen`).
    var onSearchOpen: () -> Void = { }
    /// Stores the exercise, adds its row, and shows it.
    let onCreate: (CreatedExercise) async -> Void
    /// How many routines use the exercise, for Delete's question.
    let routineCount: (Exercise.ID) -> Int
    /// Deletes the created exercise and its rows.
    let onDelete: (Exercise.ID) async -> Void
    /// The exercise's Customize form; its closure goes back a page.
    @ViewBuilder let customize: (Exercise.ID, _ back: @escaping () -> Void) -> Customize
    /// A created row's values.
    @ViewBuilder let values: (RoutineExercise.ID) -> Values

    /// The created exercise Delete in the hold menu is asking about.
    @State private var deleting: Exercise?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack(path: $path) {
            ExerciseListView(
                exercises: exercises,
                onTap: onPick,
                rowActions: holdMenu,
                barTitle: "Add exercise",
                barLeading: closeButton,
                onSearchOpen: onSearchOpen,
                onCreate: onCreate,
                isCovered: !path.isEmpty,
            )
            // Still the screen's title for VoiceOver; the bar shows the search's drawn copy.
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PickerPage.self) { page in
                switch page {
                case let .customize(id):
                    customize(id) { path.removeLast() }
                case let .values(id):
                    values(id)
                        // Its Close shuts the sheet; the list under it is never reached again.
                        .navigationBarBackButtonHidden()
                }
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
            Text(ExerciseForm.deleteMessage(routineCount: routineCount(exercise.id)))
        }
    }

    private func holdMenu(_ exercise: Exercise) -> HoldMenu {
        HoldMenu(
            isCreated: exercises.original(id: exercise.id) == nil,
            onCustomize: { path.append(.customize(exercise.id)) },
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

/// A page pushed in Add exercise: an exercise's Customize form, or, once Create has made it, a
/// row's values.
enum PickerPage: Hashable {
    case customize(Exercise.ID)
    case values(RoutineExercise.ID)
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
    ExercisePicker(exercises: .builtIn, path: .constant([])) { _ in } onCreate: { _ in
    } routineCount: { _ in
        0
    } onDelete: { _ in
    } customize: { _, _ in
        EmptyView()
    } values: { _ in
        EmptyView()
    }
}

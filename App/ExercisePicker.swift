import DesignSystem
import SwiftUI
import WorkoutStore

/// The sheet Add exercise opens: every built-in exercise A to Z, narrowed by search. Picking one
/// hands it back; the presenter closes the sheet.
///
/// Search does not take focus when the sheet opens. The list is the fast path: with the
/// keyboard down, the whole list is in reach of a thumb and a pick is one tap.
struct ExercisePicker: View {
    let onPick: (Exercise) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @ObserveHotReload private var hotReload

    var body: some View {
        let exercises = Exercise.builtIn.matching(query)
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    // In a scroll view, which keeps clear of the search field and the keyboard
                    // and scrolls when the text is too large for the room left. Centered over the
                    // list, it slid under both at the largest text sizes.
                    ScrollView {
                        ContentUnavailableView.search(text: query)
                    }
                    .defaultScrollAnchor(.center, for: .alignment)
                } else {
                    List(exercises) { exercise in
                        Button {
                            onPick(exercise)
                        } label: {
                            RowLabel(title: exercise.name, detail: exercise.equipmentLine)
                        }
                        .listRowBackground(Color.pp(.background))
                        .accessibilityIdentifier("picker.exercise")
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.pp(.background))
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search",
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .hotReloadable()
    }
}

#Preview {
    ExercisePicker { _ in }
}

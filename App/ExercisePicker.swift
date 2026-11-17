import DesignSystem
import SwiftUI
import WorkoutStore

/// The sheet Add exercise opens: every exercise, built-in and created, A to Z, narrowed by
/// search. Picking one hands it back; the presenter closes the sheet.
///
/// Search does not take focus when the sheet opens. The list is the fast path: with the
/// keyboard down, the whole list is in reach of a thumb and a pick is one tap.
///
/// Create follows the typing (`ExerciseList.offersCreate(for:)`): with something typed and no
/// exercise of exactly that name, Create “…” is the list's last row; with no matches it is the
/// only row, so the list narrows down to it and there is no separate no-results view. It pushes
/// `NewExerciseForm` on the sheet's own stack, so
/// Cancel comes back to the search as it was. Neutral, not green: green is data and the +.
struct ExercisePicker: View {
    let exercises: ExerciseList
    let onPick: (Exercise) -> Void
    /// Stores the exercise and adds its row; the presenter closes the sheet.
    let onCreate: (CreatedExercise) async -> Void

    @State private var query = ""
    /// The name the form opens with, while it shows.
    @State private var creating: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let matches = exercises.matching(query)
        let offersCreate = exercises.offersCreate(for: query)
        NavigationStack {
            List {
                ForEach(matches) { exercise in
                    Button {
                        onPick(exercise)
                    } label: {
                        RowLabel(title: exercise.name, detail: exercise.equipmentLine)
                    }
                    .listRowBackground(Color.pp(.background))
                    .accessibilityIdentifier("picker.exercise")
                }
                if offersCreate {
                    createRow
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            .navigationDestination(item: $creating) { name in
                NewExerciseForm(name: name, exercises: exercises, onAdd: onCreate)
            }
        }
    }

    private var createTitle: String {
        "Create \u{201C}\(trimmedQuery)\u{201D}"
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var createRow: some View {
        Button {
            creating = trimmedQuery
        } label: {
            Label(createTitle, systemImage: "plus")
                .font(.ppRowTitle)
                .makesSomething()
                // A label's separator starts at its title, past the icon; this one starts at
                // the row's edge, where a result row's does.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .listRowBackground(Color.pp(.background))
        .listRowSeparator(.hidden, edges: .bottom)
        .accessibilityIdentifier("picker.create")
    }
}

#Preview {
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: { _ in }
}

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
/// exercise of exactly that name, Create “…” is the last row of the matches, or, with none, a
/// button under the no-results view. It pushes `NewExerciseForm` on the sheet's own stack, so
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
            Group {
                if matches.isEmpty {
                    // In a scroll view, which keeps clear of the search field and the keyboard
                    // and scrolls when the text is too large for the room left. Centered over the
                    // list, it slid under both at the largest text sizes.
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                            ContentUnavailableView.search(text: query)
                            if offersCreate {
                                createButton
                            }
                        }
                    }
                    .defaultScrollAnchor(.center, for: .alignment)
                } else {
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
            .navigationDestination(isPresented: Binding {
                creating != nil
            } set: { isShown in
                if !isShown {
                    creating = nil
                }
            }) {
                if let creating {
                    NewExerciseForm(name: creating, exercises: exercises, onAdd: onCreate)
                }
            }
        }
    }

    private var createTitle: String {
        "Create \u{201C}\(trimmedQuery)\u{201D}"
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var createButton: some View {
        Button {
            creating = trimmedQuery
        } label: {
            Label(createTitle, systemImage: "plus")
                .font(.ppButton)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.pp(.textPrimary))
        .padding(.horizontal, Spacing.lg)
        .accessibilityIdentifier("picker.create")
    }

    private var createRow: some View {
        Button {
            creating = trimmedQuery
        } label: {
            Label(createTitle, systemImage: "plus")
                .font(.ppRowTitle)
                .foregroundStyle(Color.pp(.textPrimary))
        }
        .listRowBackground(Color.pp(.background))
        .listRowSeparator(.hidden, edges: .bottom)
        .accessibilityIdentifier("picker.create")
    }
}

#Preview {
    ExercisePicker(exercises: .builtIn) { _ in } onCreate: { _ in }
}

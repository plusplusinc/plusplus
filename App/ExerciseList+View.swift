import DesignSystem
import SwiftUI
import WorkoutStore

/// Every exercise, built-in and created, A to Z under letter headings, narrowed by search: the
/// one list both Add exercise (`ExercisePicker`) and Exercises (`ExercisesScreen`) show. They
/// differ only in what a tap on a row does and in how they open.
///
/// Down the trailing edge, the system's section index lists the letters that have an exercise
/// (`lettered()`), in green; a tap on one jumps to its heading, and a drag along it scrubs
/// through them. VoiceOver reads it as one adjustable "Section index". It hides while
/// searching, when the matches are few and the keyboard covers most of it.
///
/// Search does not take focus when the list opens. The list is the fast path: with the
/// keyboard down, the whole list is in reach of a thumb and a pick is one tap.
///
/// Create follows the typing (`ExerciseList.offersCreate(for:)`): with something typed and no
/// exercise of exactly that name, Create “…” is the list's last row, green as what makes
/// something is; with no matches it is the only row, so the list narrows down to it and there
/// is no separate no-results view. It pushes `ExerciseForm` on the host's own stack, so
/// Cancel comes back to the search as it was.
struct ExerciseListView: View {
    let exercises: ExerciseList
    /// What a tap on a row does; nil leaves every row a plain row that opens nothing.
    let onTap: ((Exercise) -> Void)?
    /// Which rows take a tap; the rest are plain rows that open nothing.
    var isTappable: (Exercise) -> Bool = { _ in true }
    /// Whether the form goes back to the list once it has created, rather than its host
    /// closing around it. Its button reads Create there, since nothing goes into a routine,
    /// and Add where it does.
    var returnsAfterCreate = false
    /// Stores the exercise; the host decides what shows next.
    let onCreate: (CreatedExercise) async -> Void

    @State private var query = ""
    /// The name the form opens with, while it shows.
    @State private var creating: String?

    var body: some View {
        let sections = exercises.matching(query).lettered()
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.exercises, content: row)
                } header: {
                    Text(section.letter)
                        .font(.ppRowDetail)
                        .fontWeight(.semibold)
                        .foregroundStyle(.pp(.textSecondary))
                }
                .sectionIndexLabel(Text(section.letter))
            }
            if exercises.offersCreate(for: query) {
                createRow
            }
        }
        .listStyle(.plain)
        .listSectionIndexVisibility(query.isEmpty ? .visible : .hidden)
        // The index takes the tint: green, as in the design, rather than the system's blue,
        // which in this app marks something arriving.
        .tint(.pp(.accent))
        .scrollContentBackground(.hidden)
        // Behind the whole screen, not the list's frame: the list gives the keyboard its room
        // and takes it back more slowly than the keyboard leaves, and the window's black showed
        // in between.
        .containerBackground(Color.pp(.background), for: .navigation)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search",
        )
        .navigationDestination(item: $creating) { name in
            ExerciseForm(
                name: name,
                exercises: exercises,
                confirmTitle: returnsAfterCreate
                    ? String(localized: "Create") : String(localized: "Add"),
            ) { created in
                await onCreate(created)
                if returnsAfterCreate {
                    creating = nil
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ exercise: Exercise) -> some View {
        let label = RowLabel(title: exercise.name, detail: exercise.equipmentLine)
        Group {
            if let onTap, isTappable(exercise) {
                Button {
                    onTap(exercise)
                } label: {
                    label
                }
            } else {
                label.accessibilityElement(children: .combine)
            }
        }
        .listRowBackground(Color.pp(.background))
        .accessibilityIdentifier("exercises.row")
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var createRow: some View {
        Button {
            creating = trimmedQuery
        } label: {
            Label("Create \u{201C}\(trimmedQuery)\u{201D}", systemImage: "plus")
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
    NavigationStack {
        ExerciseListView(exercises: .builtIn, onTap: nil) { _ in }
            .navigationTitle("Exercises")
    }
}

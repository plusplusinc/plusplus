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
/// searching and while the keyboard is up, when the matches are few and the keyboard covers
/// most of it.
///
/// Exercises has its search in the bar beside Back (`BarSearchField`); Add exercise has the
/// system's, in a drawer under its title.
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
    /// Whether search sits in the bar's middle, in line with Back (`BarSearchField`), rather
    /// than in a drawer under the title.
    var searchesInBar = false
    /// Stores the exercise; the host decides what shows next.
    let onCreate: (CreatedExercise) async -> Void

    @State private var query = ""
    /// The name the form opens with, while it shows.
    @State private var creating: String?
    @State private var isKeyboardUp = false

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
                .indexLabel(section.letter, isShown: showsIndex)
            }
            if exercises.offersCreate(for: query) {
                createRow
            }
        }
        .listStyle(.plain)
        // From the keyboard's start up to the end of its way down: the index fits itself to the
        // list's room, which follows the keyboard, and shown meanwhile it squashed to a third of
        // its height and grew back.
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification,
        )) { _ in
            isKeyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardDidHideNotification,
        )) { _ in
            isKeyboardUp = false
        }
        // The index takes the tint: green, as in the design, rather than the system's blue,
        // which in this app marks something arriving.
        .tint(.pp(.accent))
        .scrollContentBackground(.hidden)
        // Behind the whole screen, not the list's frame: the list gives the keyboard its room
        // and takes it back more slowly than the keyboard leaves, and the window's black showed
        // in between.
        .containerBackground(Color.pp(.background), for: .navigation)
        .searchField(text: $query, inBar: searchesInBar)
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

    private var showsIndex: Bool {
        query.isEmpty && !isKeyboardUp
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

extension View {
    /// The section's letter in the index, or none. The index drops out with its labels; a
    /// change to `listSectionIndexVisibility` alone left it shown until the list's rows changed.
    @ViewBuilder
    fileprivate func indexLabel(_ letter: String, isShown: Bool) -> some View {
        if isShown {
            sectionIndexLabel(Text(letter))
        } else {
            self
        }
    }

    fileprivate func searchField(text: Binding<String>, inBar: Bool) -> some View {
        modifier(SearchField(text: text, inBar: inBar))
    }
}

/// Search in a drawer under the title, the system's, or in the bar beside Back.
private struct SearchField: ViewModifier {
    @Binding var text: String
    let inBar: Bool

    /// The screen's width, which the bar's field spans but for Back.
    @State private var width: CGFloat = 0

    /// What the field leaves of the bar's width: the margins on both sides, Back, and the gap
    /// after it. A bar item hugs its content, and the middle one stays centered, so the field
    /// gets its width from the screen's.
    private static let besideBack: CGFloat = 16 + 44 + 8 + 16

    func body(content: Content) -> some View {
        if inBar {
            content
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        BarSearchField(text: $text, prompt: "Search")
                            .frame(width: max(0, width - Self.besideBack))
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                // As the system's search does: a drag down the list drops the keyboard.
                .scrollDismissesKeyboard(.immediately)
        } else {
            content.searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search",
            )
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseListView(exercises: .builtIn, onTap: nil) { _ in }
            .navigationTitle("Exercises")
    }
}

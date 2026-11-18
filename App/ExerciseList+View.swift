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
/// Both have search as a round button at the bar's top trailing edge, which opens out to the
/// left into a field across the bar (`BarSearchField`), taking in the bar's leading button: ++ in
/// Exercises, under its large title, and Close in Add exercise, where the field covers the inline
/// title too.
///
/// Search does not take focus when the list opens. The list is the fast path: with the
/// keyboard down, the whole list is in reach of a thumb and a pick is one tap.
///
/// Create follows the typing (`ExerciseList.offersCreate(for:)`): with something typed and no
/// exercise of exactly that name, Create “…” is the list's last row, green as what makes
/// something is; with no matches it is the only row, so the list narrows down to it and there
/// is no separate no-results view. It pushes `ExerciseForm` on the host's own stack, so
/// Cancel comes back to the search as it was.
struct ExerciseListView<BarLeading: View>: View {
    let exercises: ExerciseList
    /// What a tap on a row does.
    let onTap: (Exercise) -> Void
    /// Which rows take a tap; the rest are plain rows that open nothing.
    var isTappable: (Exercise) -> Bool = { _ in true }
    /// Whether the form goes back to the list once it has created, rather than its host
    /// closing around it. Its button reads Create there, since nothing goes into a routine,
    /// and Add where it does.
    var returnsAfterCreate = false
    /// The host's inline title, drawn by the bar's search so its field covers the title as it
    /// opens; nil leaves the bar's own title.
    var barTitle: LocalizedStringKey?
    /// The host's leading bar button, drawn by the bar's search in its own item so its field
    /// takes the button's place as it opens; the host puts none in its toolbar.
    let barLeading: BarLeading
    /// Stores the exercise; the host decides what shows next.
    let onCreate: (CreatedExercise) async -> Void

    @State private var query = ""
    /// The name the form opens with, while it shows.
    @State private var creating: String?
    @State private var isKeyboardUp = false
    /// Where the list's room starts, at the bar's bottom edge, in global coordinates: where a
    /// heading pins, and past which a heading pushed up fades (`LeavesUnderBar`).
    @State private var listTop: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

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
                        .modifier(LeavesUnderBar(listTop: listTop))
                }
                .indexLabel(section.letter, isShown: showsIndex)
            }
            if exercises.offersCreate(for: query) {
                createRow
            }
        }
        .listStyle(.plain)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
            listTop = $0
        }
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
        .modifier(SearchField(text: $query, title: barTitle, leading: barLeading))
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
            if isTappable(exercise) {
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

    /// The name Create makes, as its row shows it and its form opens with it.
    private var createdName: String {
        ExerciseList.createdName(from: query)
    }

    private var createRow: some View {
        Button {
            creating = createdName
        } label: {
            createLabel
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

    /// At the accessibility sizes the title wraps beside the +, in a column of its own: a list's
    /// label there ran its second line back under the +, past its own frame, and the audit
    /// read it as clipped.
    @ViewBuilder
    private var createLabel: some View {
        let title = Text("Create \u{201C}\(createdName)\u{201D}")
        if typeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Image(systemName: "plus")
                    .accessibilityHidden(true)
                title
            }
        } else {
            Label { title } icon: { Image(systemName: "plus") }
        }
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
}

/// Fades a letter heading out over its own height as the next one pushes it up past the bar's
/// bottom edge, where it pins. The list draws its pinned headings above the bar's edge effect,
/// which blurs the rows under the bar: unfaded, a heading pushed up went on sharp under the bar
/// and the clock until its section's end left the screen.
private struct LeavesUnderBar: ViewModifier {
    let listTop: CGFloat

    func body(content: Content) -> some View {
        content.visualEffect { [listTop] content, proxy in
            let frame = proxy.frame(in: .global)
            let past = listTop - frame.minY
            return content.opacity(1 - min(max(past / max(frame.height, 1), 0), 1))
        }
    }
}

/// Search as `BarSearchField`, one bar item holding the host's leading button and the round
/// search button, spanning the bar between its margins. A bar item hugs its content, so the item
/// gets its width from the screen's. Given a title, the bar's own inline title is removed and
/// `BarSearchField` draws it, centered on the screen, for its field to cover; the screen keeps it
/// as its navigation title.
private struct SearchField<Leading: View>: ViewModifier {
    @Binding var text: String
    let title: LocalizedStringKey?
    let leading: Leading

    /// The screen's width, which the item spans but for the bar's margins.
    @State private var width: CGFloat = 0
    /// The screen's middle in global coordinates, where a drawn title centers.
    @State private var midX: CGFloat = 0
    /// Held here, not in the item: the bar reads its item's elements again only as the host's
    /// state changes (`BarSearchField`).
    @State private var isOpen = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
                // Only a drawn title reads it; Exercises' moves with every frame of the drawer.
                if title != nil {
                    midX = $0
                }
            }
            .toolbar(removing: title == nil ? nil : .title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BarSearchField(
                        text: $text,
                        isOpen: $isOpen,
                        prompt: "Search",
                        width: width - 2 * Spacing.md,
                        title: title,
                        titleCenterX: midX,
                    ) { leading }
                        .hiddenBehindDrawer()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            // As the system's search does: a drag down the list drops the keyboard.
            .scrollDismissesKeyboard(.immediately)
    }
}

#Preview {
    NavigationStack {
        ExerciseListView(
            exercises: .builtIn,
            onTap: { _ in },
            barLeading: EmptyView(),
            onCreate: { _ in },
        )
        .navigationTitle("Exercises")
    }
}

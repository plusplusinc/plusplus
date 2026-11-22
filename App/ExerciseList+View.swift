import DesignSystem
import SwiftUI
import WorkoutStore

/// Every exercise, built-in and created, A to Z under letter headings, narrowed by search: the
/// list Add exercise (`ExercisePicker`) shows.
///
/// Down the trailing edge, the system's section index lists the letters that have an exercise
/// (`lettered()`), in green; a tap on one jumps to its heading, and a drag along it scrubs
/// through them. VoiceOver reads it as one adjustable "Section index". It hides while
/// searching and while the keyboard is up, when the matches are few and the keyboard covers
/// most of it.
///
/// Search is a round button at the bar's top trailing edge, which opens out to the left into a
/// field across the bar (`BarSearchField`), which the bar's leading button, Close, turns into.
/// The field covers the bar's title too.
///
/// Search does not take focus when the list opens. The list is the fast path: with the
/// keyboard down, the whole list is in reach of a thumb and a pick is one tap.
///
/// Create follows the typing (`ExerciseList.offersCreate(for:)`): with something typed and no
/// exercise of exactly that name, Create “…” is the list's last row, green as what makes
/// something is; with no matches it is the only row, so the list narrows down to it and there
/// is no separate no-results view. A tap makes the exercise at once, with that name and nothing
/// else set (`ExerciseList.createdName(from:)`), and hands it to the host.
struct ExerciseListView<BarLeading: View, RowActions: ViewModifier>: View {
    let exercises: ExerciseList
    /// What a tap on a row does.
    let onTap: (Exercise) -> Void
    /// What else a row does, on its row: Add exercise's hold menu.
    let rowActions: (Exercise) -> RowActions
    /// The host's inline title, drawn by the bar's search so its field covers the title as it
    /// opens.
    let barTitle: LocalizedStringKey
    /// The host's leading bar button, drawn by the bar's search in its own item so its field
    /// takes the button's place as it opens; the host puts none in its toolbar.
    let barLeading: BarLeading
    /// Runs as search opens, in the tap's own transaction, so what it changes moves with the
    /// field: Add exercise's sheet goes to full height.
    var onSearchOpen: () -> Void = { }
    /// Stores the exercise and shows it.
    let onCreate: (CreatedExercise) async -> Void

    /// What the list is narrowed by, started from the opening's.
    @State private var filter: ExerciseFilter
    /// The filter whose sheet of chips is up.
    @State private var choosing: FilterSheet?
    @State private var query = ""
    /// While a Create's store lands: a second tap meanwhile would make a second exercise.
    @State private var isCreating = false
    @State private var isKeyboardUp = false
    /// Where the list's room starts, at the filter row's bottom edge, in global coordinates: where
    /// a
    /// heading pins, and past which a heading pushed up fades (`LeavesUnderBar`).
    @State private var listTop: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        exercises: ExerciseList,
        filter: ExerciseFilter = ExerciseFilter(),
        onTap: @escaping (Exercise) -> Void,
        rowActions: @escaping (Exercise) -> RowActions,
        barTitle: LocalizedStringKey,
        barLeading: BarLeading,
        onSearchOpen: @escaping () -> Void = { },
        onCreate: @escaping (CreatedExercise) async -> Void,
    ) {
        self.exercises = exercises
        _filter = State(initialValue: filter)
        self.onTap = onTap
        self.rowActions = rowActions
        self.barTitle = barTitle
        self.barLeading = barLeading
        self.onSearchOpen = onSearchOpen
        self.onCreate = onCreate
    }

    var body: some View {
        list
            .safeAreaBar(edge: .top) { filterBar }
            .sheet(item: $choosing) { sheet in
                switch sheet {
                case .muscle:
                    ChipSheet(
                        title: "Muscle",
                        items: MuscleGroup.allCases,
                        chosen: $filter.muscleGroups,
                        name: \.name,
                        onDone: { choosing = nil },
                    )
                case .equipment:
                    ChipSheet(
                        title: "Equipment",
                        items: EquipmentChoice.allCases,
                        chosen: $filter.equipment,
                        name: \.name,
                        onDone: { choosing = nil },
                    )
                }
            }
            .modifier(SearchField(
                text: $query,
                title: barTitle,
                leading: barLeading,
                onOpen: onSearchOpen,
            ))
    }

    /// The three filters' buttons, alike whatever they open, wrapping when their words don't
    /// fit one line; under them, while one is on, the count and Clear.
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: Spacing.sm) {
                Button {
                    dropKeyboard()
                    choosing = .muscle
                } label: {
                    FilterLabel(
                        filter.muscleLabel ?? "Muscle",
                        isOn: !filter.muscleGroups.isEmpty,
                    )
                }
                .buttonStyle(.plain)
                kindMenu
                Button {
                    dropKeyboard()
                    choosing = .equipment
                } label: {
                    FilterLabel(
                        filter.equipmentLabel ?? "Equipment",
                        isOn: !filter.equipment.isEmpty,
                    )
                }
                .buttonStyle(.plain)
            }
            if filter.isOn {
                FilterCount(countText) {
                    filter = ExerciseFilter()
                }
                .padding(.bottom, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
            listTop = $0
        }
    }

    /// Kind takes one at a time, so it is the system's menu: a toggle per kind, the chosen one
    /// checked; picking it again clears it.
    private var kindMenu: some View {
        Menu {
            ForEach(ExerciseKind.allCases, id: \.self) { kind in
                Toggle(kind.name, isOn: Binding {
                    filter.kind == kind
                } set: { _ in
                    filter.toggle(kind)
                })
            }
        } label: {
            FilterLabel(filter.kindLabel ?? "Kind", isOn: filter.kind != nil)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
    }

    private var countText: String {
        let count = exercises.filtered(by: filter, matching: query).matches.count
        return count == 1 ? "1 exercise" : "\(count) exercises"
    }

    private var list: some View {
        List {
            if filter.isOn {
                ForEach(exercises.filtered(by: filter, matching: query).matches, content: row)
            } else {
                ForEach(exercises.matching(query).lettered()) { section in
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
    }

    private var showsIndex: Bool {
        query.isEmpty && !isKeyboardUp
    }

    private func row(_ exercise: Exercise) -> some View {
        Button {
            dropKeyboard()
            onTap(exercise)
        } label: {
            RowLabel(title: exercise.name, detail: exercise.equipmentLine)
        }
        .modifier(rowActions(exercise))
        .listRowBackground(Color.pp(.background))
        .accessibilityIdentifier("exercises.row")
    }

    /// Ends the search's editing at a tap that pushes a screen, so the keyboard goes down with
    /// the push, as the system's search does; back on the list, search stays open with its text,
    /// keyboard down. Through the responder chain: the field is in a bar item, hosted apart from
    /// the list, and a `FocusState` of the list's bound to it never took focus as it opened.
    private func dropKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil,
        )
    }

    /// The name Create makes, as its row shows it.
    private var createdName: String {
        ExerciseList.createdName(from: query)
    }

    private var createRow: some View {
        Button {
            guard !isCreating else { return }
            dropKeyboard()
            isCreating = true
            let created = CreatedExercise(name: createdName, muscleGroups: [])
            Task {
                await onCreate(created)
                isCreating = false
            }
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

/// A filter that takes several choices, and so opens a sheet of chips.
private enum FilterSheet: Identifiable {
    case muscle
    case equipment

    var id: Self {
        self
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
/// gets its width from the screen's. The bar's own inline title is removed and `BarSearchField`
/// draws the title, centered on the screen, for its field to cover; the screen keeps it as its
/// navigation title.
private struct SearchField<Leading: View>: ViewModifier {
    @Binding var text: String
    let title: LocalizedStringKey
    let leading: Leading
    let onOpen: () -> Void

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
                midX = $0
            }
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BarSearchField(
                        text: $text,
                        // `BarSearchField` turns it inside the open's animation, so `onOpen`
                        // runs in that transaction, not after it, as an `onChange` would.
                        isOpen: Binding {
                            isOpen
                        } set: { open in
                            isOpen = open
                            if open {
                                onOpen()
                            }
                        },
                        prompt: "Search",
                        width: width - 2 * Spacing.md,
                        title: title,
                        titleCenterX: midX,
                    ) { leading }
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
            rowActions: { _ in EmptyModifier() },
            barTitle: "Add exercise",
            barLeading: EmptyView(),
            onCreate: { _ in },
        )
        .navigationTitle("Add exercise")
    }
}

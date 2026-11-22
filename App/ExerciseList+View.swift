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
    /// Runs as search opens, or a filter's button is tapped, in the tap's own transaction, so
    /// what it changes moves with the field or the filter: Add exercise's sheet goes to full
    /// height.
    var onExpand: () -> Void = { }
    /// Stores the exercise and shows it; the flag says whether it still needs its name, made
    /// with nothing typed.
    let onCreate: (CreatedExercise, _ needsName: Bool) async -> Void

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

    init(
        exercises: ExerciseList,
        filter: ExerciseFilter = ExerciseFilter(),
        onTap: @escaping (Exercise) -> Void,
        rowActions: @escaping (Exercise) -> RowActions,
        barTitle: LocalizedStringKey,
        barLeading: BarLeading,
        onExpand: @escaping () -> Void = { },
        onCreate: @escaping (CreatedExercise, _ needsName: Bool) async -> Void,
    ) {
        self.exercises = exercises
        _filter = State(initialValue: filter)
        self.onTap = onTap
        self.rowActions = rowActions
        self.barTitle = barTitle
        self.barLeading = barLeading
        self.onExpand = onExpand
        self.onCreate = onCreate
    }

    var body: some View {
        let filtered = exercises.filtered(by: filter, matching: query)
        list(filtered)
            .safeAreaBar(edge: .top) { filterBar(count: filtered.matches.count) }
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
                onOpen: onExpand,
            ))
    }

    /// The three filters' buttons, alike whatever they open, on one line that scrolls sideways
    /// when their words don't fit (decided 2026-11-22: the row never wraps); under them, while
    /// one is on, the count and Clear. A tap on any of them takes Add exercise to full height,
    /// as search does (decided 2026-11-22), so a sheet of chips sits over the list, which shows
    /// above it narrowing with each tap.
    private func filterBar(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    Button {
                        open(.muscle)
                    } label: {
                        FilterLabel(
                            filter.muscleLabel ?? "Muscle",
                            isOn: !filter.muscleGroups.isEmpty,
                        )
                    }
                    .buttonStyle(.plain)
                    kindMenu
                    Button {
                        open(.equipment)
                    } label: {
                        FilterLabel(
                            filter.equipmentLabel ?? "Equipment",
                            isOn: !filter.equipment.isEmpty,
                        )
                    }
                    .buttonStyle(.plain)
                }
                // Inside the scroll's content, so the first button lines up with the rows and
                // the last scrolls clear of the edge.
                .padding(.horizontal, Spacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if filter.isOn {
                FilterCount(count == 1 ? "1 exercise" : "\(count) exercises") {
                    filter = ExerciseFilter()
                }
                .padding(.horizontal, Spacing.md)
                // Clear is a button of its own now, so the line stands off the filters'
                // buttons by more than the gap between two of them.
                .padding(.top, Spacing.sm + Spacing.xs)
                .padding(.bottom, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
            listTop = $0
        }
    }

    private func open(_ sheet: FilterSheet) {
        dropKeyboard()
        onExpand()
        choosing = sheet
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
        // A menu reports no opening of its own; this tap is the one that opens it.
        .simultaneousGesture(TapGesture().onEnded {
            dropKeyboard()
            onExpand()
        })
    }

    private func list(_ filtered: FilteredExercises) -> some View {
        List {
            if filter.isOn {
                ForEach(filtered.matches, content: row)
                if query.isEmpty || exercises.offersCreate(for: query) {
                    createRow
                }
                ForEach(filtered.alsoNeeds) { section in
                    Section {
                        ForEach(section.exercises, content: row)
                    } header: {
                        NeedsHeader(
                            title: "Also needs \(section.piece.needed)",
                            addTitle: section.piece.name,
                        ) {
                            filter.equipment.insert(.piece(section.piece))
                        }
                        .modifier(LeavesUnderBar(listTop: listTop))
                    }
                }
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
                if exercises.offersCreate(for: query) {
                    createRow
                }
            }
        }
        .listStyle(.plain)
        // A new filter is a new list, from its top, with no scroll to watch: the results are
        // new. The filter is the list's identity, not a scroll asked from a change.
        .id(filter)
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

    /// Create: with something typed, Create "…" makes an exercise of that name; with nothing
    /// typed, under a filter, "Create exercise" makes one named
    /// `ExerciseList.unnamedExerciseName`, whose Customize opens with the name to type over.
    /// Either way it starts with the filter's groups and equipment (`ExerciseFilter.carried…`),
    /// which the row's detail line shows.
    private var createRow: some View {
        let needsName = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            guard !isCreating else { return }
            dropKeyboard()
            isCreating = true
            let created = CreatedExercise(
                name: needsName
                    ? exercises.unusedName(ExerciseList.unnamedExerciseName)
                    : ExerciseList.createdName(from: query),
                muscleGroups: filter.carriedGroups,
                equipment: filter.carriedEquipment,
            )
            Task {
                await onCreate(created, needsName)
                isCreating = false
            }
        } label: {
            CreateLabel(
                title: needsName
                    ? "Create exercise"
                    : "Create \u{201C}\(ExerciseList.createdName(from: query))\u{201D}",
                detail: filter.carriedLine,
            )
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

#Preview {
    NavigationStack {
        ExerciseListView(
            exercises: .builtIn,
            onTap: { _ in },
            rowActions: { _ in EmptyModifier() },
            barTitle: "Add exercise",
            barLeading: EmptyView(),
            onCreate: { _, _ in },
        )
        .navigationTitle("Add exercise")
    }
}

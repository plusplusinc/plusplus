import DesignSystem
import SwiftUI
import WorkoutStore

/// Every exercise, built-in and created, A to Z under letter headings, narrowed by search and
/// by filters: the list Add exercise (`ExercisePicker`) shows.
///
/// Under the bar, the filters' buttons, Muscle, Kind, and Equipment (`FilterBar`), start from
/// the opening's filter. While one is on, the list is one list with no letter headings and no
/// index: the matches, those that mainly work a chosen muscle first
/// (`ExerciseList.filtered(by:matching:)`); then Create; then an "Also needs" section for each
/// piece one short of the chosen equipment, headed by a button that adds it (`NeedsHeader`).
/// The first row has no line over it, where it would rule off the buttons. Each change puts
/// the list back at its top and tells VoiceOver the count. Muscle and Equipment choose in a
/// sheet of chips (`ChipSheet`), applied with each tap.
///
/// Down the trailing edge, the system's section index lists the letters that have an exercise
/// (`lettered()`), in green; a tap on one jumps to its heading, and a drag along it scrubs
/// through them. VoiceOver reads it as one adjustable "Section index". It hides while
/// searching and while the keyboard is up, when the matches are few and the keyboard covers
/// most of it, while a filter's sheet is up, and goes with the headings under a filter.
///
/// Search is a round button at the bar's top trailing edge, which opens out to the left into a
/// field across the bar (`BarSearchField`), which the bar's leading button, Close, turns into.
/// The field covers the bar's title too.
///
/// A typed word that names a filter's choice, "back" or "dumbbells", offers it on a line under
/// the filters' buttons (`FilterOffer`, `FilterOfferLine`): a tap turns the choice on, takes
/// the word out of the search, and leaves the keyboard up, the field keeping its caret; VoiceOver
/// hears the new count.
///
/// Search does not take focus when the list opens. The list is the fast path: with the
/// keyboard down, the whole list is in reach of a thumb and a pick is one tap.
///
/// Create follows the typing (`ExerciseList.offersCreate(for:)`): with something typed and no
/// exercise of exactly that name, Create “…” is the list's last row, green as what makes
/// something is; with no matches it is the only row, so the list narrows down to it and there
/// is no separate no-results view. Under a filter it is the matches' last row even with
/// nothing typed, "Create exercise", with a line of what it carries (`createRow(isFirst:)`).
/// A tap makes the exercise at once (`ExerciseList.createdName(from:)`) and hands it to the
/// host.
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
    /// Runs as search opens, or Muscle's or Equipment's button is tapped, in the tap's own
    /// transaction, so what it changes moves with the field or the filter: Add exercise's sheet
    /// goes to full height.
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
    /// Where the list's room starts, at the filter row's bottom edge, in global coordinates:
    /// where a heading pins, and past which a heading pushed up fades (`LeavesUnderBar`).
    @State private var listTop: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // The list's identity is its filter (`list(_:)`); in a container of its own, so a new
        // filter replaces the list alone. Straight on the list, the bar was replaced with it,
        // and its buttons popped where they should slide.
        ZStack { list(filtered) }
            // The system picked the hard edge while typing, a hairline under the bar over a
            // lighter band; the soft one, as with the keyboard down, either way.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) {
                FilterBar(
                    filter: announcedFilter,
                    onOpen: open,
                    offers: FilterOffer.offers(in: query, given: filter),
                    onTake: take,
                )
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                    listTop = $0
                }
            }
            .sheet(item: $choosing) { sheet in
                switch sheet {
                case .muscle:
                    ChipSheet(
                        title: "Muscle",
                        items: MuscleGroup.allCases,
                        chosen: announcedFilter.muscleGroups,
                        name: \.name,
                        onDone: { choosing = nil },
                    )
                case .equipment:
                    ChipSheet(
                        title: "Equipment",
                        items: EquipmentChoice.allCases,
                        chosen: announcedFilter.equipment,
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

    /// A tap on a filter that opens a sheet of chips, Muscle or Equipment, takes Add exercise to
    /// full height, as search does (decided 2026-11-22), so the chips sit over the list, which
    /// shows above them narrowing with each tap.
    private func open(_ sheet: FilterSheet) {
        dropKeyboard()
        onExpand()
        choosing = sheet
    }

    /// Takes an offer: its choice on, its words out of the search, which stays open with the
    /// keyboard up. The text changes first, so the count VoiceOver hears is the list's.
    private func take(_ offer: FilterOffer) {
        // One transaction for both: the offer line leaving with its words and the filter's
        // change. The text alone, outside it, took the line away at once and the buttons moved
        // frames later.
        withAnimation(.filterChange(reduceMotion: reduceMotion)) {
            query = offer.remainingText
            announcedFilter.wrappedValue.turnOn(offer.choice)
        }
    }

    /// The filter, written through one place, which tells VoiceOver how many exercises show
    /// after each change: it cannot glance at the list behind a sheet of chips. At the write,
    /// not from a change of the filter, which can be skipped. Every change, Clear, an offer, a
    /// chip, is one `.tapChange` transaction, so the filter buttons move alike on and off.
    private var announcedFilter: Binding<ExerciseFilter> {
        Binding { filter } set: { changed in
            withAnimation(.filterChange(reduceMotion: reduceMotion)) { filter = changed }
            let count = exercises.filtered(by: changed, matching: query).matches.count
            AccessibilityNotification.Announcement(FilterBar.countText(count)).post()
        }
    }

    private func list(_ filtered: FilteredExercises) -> some View {
        List {
            if filter.isOn {
                ForEach(filtered.matches) { exercise in
                    row(exercise)
                        .listRowSeparator(
                            exercise.id == filtered.matches.first?.id ? .hidden : .automatic,
                            edges: .top,
                        )
                }
                if ExerciseList.createdName(from: query).isEmpty || exercises
                    .offersCreate(for: query)
                {
                    createRow(isFirst: filtered.matches.isEmpty)
                }
                ForEach(filtered.alsoNeeds) { section in
                    Section {
                        ForEach(section.items, content: row)
                    } header: {
                        NeedsHeader(
                            needed: section.piece.needed,
                            addTitle: section.piece.name,
                        ) {
                            announcedFilter.wrappedValue.equipment.insert(.piece(section.piece))
                        }
                        .modifier(LeavesUnderBar(listTop: listTop))
                    }
                }
            } else {
                // With no filter on, the matches are the search's alone.
                ForEach(filtered.matches.lettered()) { section in
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
                    createRow(isFirst: filtered.matches.isEmpty)
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

    /// Not under a filter's sheet either: the sheet floats clear of the screen's edges, and the
    /// index's letters showed down its side.
    private var showsIndex: Bool {
        query.isEmpty && !isKeyboardUp && choosing == nil
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
    private func createRow(isFirst: Bool) -> some View {
        let typed = ExerciseList.createdName(from: query)
        let needsName = typed.isEmpty
        return Button {
            guard !isCreating else { return }
            dropKeyboard()
            isCreating = true
            let created = CreatedExercise(
                name: needsName ? exercises.unusedName(ExerciseList.unnamedExerciseName) : typed,
                muscleGroups: filter.carriedGroups,
                equipment: filter.carriedEquipment,
            )
            Task {
                await onCreate(created, needsName)
                isCreating = false
            }
        } label: {
            CreateLabel(
                title: needsName ? "Create exercise" : "Create \u{201C}\(typed)\u{201D}",
                detail: filter.carriedLine,
            )
            .font(.ppRowTitle)
            .makesSomething()
            // A label's separator starts at its title, past the icon; this one starts at
            // the row's edge, where a result row's does.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .listRowBackground(Color.pp(.background))
        // No line under it, which would close a list that goes on to "Also needs"; and none
        // over it as the list's first row, where it ruled off the filters' buttons with unequal
        // room on its two sides. After a match, the line between the two stays: a line between
        // two rows goes when either hides its side of it.
        .listRowSeparator(.hidden, edges: isFirst ? .all : .bottom)
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

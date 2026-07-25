import SwiftUI
import SwiftData
import PlusPlusKit

/// ONE view per catalog type, rendered by BOTH the tab and the search scope
/// (Dave, 2026-07-25): tapping **Routines** with search closed and scoping to
/// **Routines** with it open land here, on the same screen. Search only adds a
/// query. That is the whole point of this file — the universal-search surface
/// had become a second copy of the three catalog tabs, so the two became one.
///
/// It replaces four screens: `RoutineListView`, `ExercisesTabView`,
/// `EquipmentTabView`, `FindOrCreateView`, and the pushed
/// `EquipmentCatalogScreen`.
///
/// **What it shows.** `FindOrCreateEngine.sections` for the scope: MINE then
/// CATALOG, each tier carrying its own collapsible "N … require more equipment"
/// group. With no query that IS the tab's list, in the caller's own order (so a
/// user's routine drag-ordering survives — see the engine's `rank`); typing
/// narrows and ranks it.
///
/// **No facet chips, on any scope** (Dave, 2026-07-25). The three read alike.
/// Muscle groups and equipment categories both sit in the engine's fuzzy
/// haystack already, so typing reaches what the chips used to.
///
/// **Swipe law, shared by all three:** LEADING is curation (favorite, kit
/// membership), TRAILING is destructive (delete your own). Templates and
/// catalog rows with neither are plain rows; their quick acts live in the
/// long-press context menu.
struct CatalogScopeView: View {

    /// Where this surface is mounted. The list is identical either way; the
    /// chrome, the search field, and the push mechanism differ.
    enum Mode: Equatable {
        /// A tab root: owns a `NavigationStack`, and the search field is the
        /// bottom bar's (which is why `query` arrives as a binding).
        case tab
        /// Presented inside someone else's stack (a sheet, or Today's setup
        /// push) with the pushed-screen chrome and its own header field. This
        /// is what the retired `EquipmentCatalogScreen` was.
        case presented(setupMode: Bool)
        /// A PICKER sheet (Dave, 2026-07-25): the same contents as the tab,
        /// but a row tap hands the item back to the caller instead of pushing
        /// its detail, and the field sits at the BOTTOM of the sheet — where
        /// the app's own field lives, and within thumb reach of a sheet that
        /// opened from down there.
        case picker

        var isTab: Bool { self == .tab }

        /// Onboarding's guided equipment step: a pinned Done bar, no kit
        /// switcher, and the stripped detail screen.
        var setupMode: Bool {
            if case .presented(let setup) = self { return setup }
            return false
        }
    }

    /// What a presented surface pushes. A tab root uses its `NavigationPath`
    /// instead; presented surfaces sit BENEATH a live `isPresented:`/item
    /// destination, where a value append would break back-pop (#291), so they
    /// push with an item destination of their own.
    enum Push: Identifiable, Hashable {
        case exercise(Exercise)
        case equipment(Equipment)

        var id: PersistentIdentifier {
            switch self {
            case .exercise(let exercise): return exercise.persistentModelID
            case .equipment(let equipment): return equipment.persistentModelID
            }
        }
    }

    let scope: FindScope
    let mode: Mode

    /// The query. In `.tab` mode it lives in the root (the field is the bottom
    /// bar's, which sits outside every tab); in `.presented` mode the surface
    /// owns it, behind the header's expanding field.
    @Binding private var boundQuery: String
    /// Per-scope match counts, published UP to the bar's scope labels. Each
    /// mounted surface writes only its OWN key, by summing its own sections —
    /// so a surface ranks one type, not three. (The engine used to expose a
    /// `matchCounts` that ranked ALL three types for whichever surface was
    /// visible, on top of the pass that surface already ran for its own rows.)
    @Binding private var counts: [FindScope: Int]
    /// Whether the bar is pointing at this scope. All three stay mounted, so
    /// anything that answers a global signal (the field's Return key) has to
    /// know whether it is the one being talked to.
    private let isActive: Bool
    /// Picker mode only: a row tap (or a fresh create) hands the item back
    /// here instead of opening it.
    private let onPick: ((Exercise) -> Void)?
    /// Picker mode's sheet title ("Add exercise" / "Swap for…").
    private var pickerTitle = ""

    /// A tab root.
    init(
        scope: FindScope,
        query: Binding<String>,
        counts: Binding<[FindScope: Int]>,
        isActive: Bool
    ) {
        self.scope = scope
        self.mode = .tab
        self._boundQuery = query
        self._counts = counts
        self.isActive = isActive
        self.onPick = nil
    }

    /// A presented catalog (the pushed equipment catalog's replacement).
    init(scope: FindScope, setupMode: Bool = false) {
        self.scope = scope
        self.mode = .presented(setupMode: setupMode)
        self._boundQuery = .constant("")
        self._counts = .constant([:])
        self.isActive = true
        self.onPick = nil
    }

    /// A picker sheet: the same catalog, but choosing rather than browsing.
    init(picking scope: FindScope, title: String, onPick: @escaping (Exercise) -> Void) {
        self.scope = scope
        self.mode = .picker
        self._boundQuery = .constant("")
        self._counts = .constant([:])
        self.isActive = true
        self.onPick = onPick
        self.pickerTitle = title
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    /// The presented and picker forms' own query (unused in `.tab` mode, where
    /// the field is the bottom bar's and the query lives in the root).
    @State private var ownQuery = ""
    /// The picker field's one-shot focus intent. Never armed on entry — the
    /// list is the point; the keyboard rises when the field is tapped.
    @State private var pickerFieldWantsFocus = false
    @State private var path = NavigationPath()
    @State private var pushed: Push?
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    /// Which "N … require more equipment" groups are open, by `Section.id`
    /// ("MISSING_MINE" / "MISSING_CATALOG"). Collapsed by default.
    @State private var expandedMissing: Set<String> = []
    @State private var showingLibraryTray = false
    @State private var creatingExercise = false
    @State private var namingRoutine = false
    @State private var newRoutineName = ""
    @State private var namingEquipment = false
    @State private var newEquipmentName = ""
    /// The row playing the entrance flash after an add landed here.
    @State private var newlyAdded: PersistentIdentifier?
    /// Routines only: held false for one beat after an add so the new row is
    /// ABSENT from the list, then flipped inside `withAnimation` so it fades in
    /// and the rows below slide down (Dave, 2026-07-16).
    @State private var revealNewCard = false
    /// Setup mode: any engagement counts, so plain back still marks the step
    /// done. Never trap the user in a step.
    @State private var touchedSetup = false

    // MARK: - Derived state

    private var queryBinding: Binding<String> {
        mode.isTab ? $boundQuery : $ownQuery
    }

    private var isPicking: Bool { mode == .picker }

    private var trimmedQuery: String {
        queryBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    private var kitNames: Set<String> { activeLibrary?.memberNames ?? [] }

    /// The baked-in null kit is immutable: nothing lands in it, so its rows
    /// carry no membership swipe.
    private var isBodyweightKit: Bool { activeLibrary?.isBodyweight ?? false }

    /// A control label, so it always names the kit even when there's one
    /// (the one-rule naming law; prose uses `activeNamePhrase`).
    private var activeKitName: String {
        activeLibrary?.name ?? EquipmentLibrary.defaultName
    }

    /// The list, minus a just-added routine while it's held out for its
    /// entrance. Once `newlyAdded` clears the filter is a no-op.
    private var displayedRoutines: [Routine] {
        routines.filter { $0.persistentModelID != newlyAdded || revealNewCard }
    }

    private var sections: [FindOrCreateEngine.Section] {
        FindOrCreateEngine.sections(
            query: trimmedQuery,
            scope: scope,
            exercises: allExercises,
            equipment: allEquipment,
            routines: displayedRoutines,
            templates: RoutineCatalog.all,
            kitNames: kitNames
        )
    }

    /// What this surface actually draws. Everywhere except the PRESENTED
    /// equipment catalog that is `sections` verbatim.
    ///
    /// There it is one flat alphabetical run instead, because that surface is
    /// where you ADD: with MINE above CATALOG, every quick-add lifts the row
    /// you just swiped out of its place and drops it at the top, and the eight
    /// rows below it shift under your thumb. Losing your scroll position on
    /// every add is the opposite of "pick, tune, keep moving", and it lands
    /// hardest in onboarding step 1. The in-kit checkmark carries membership
    /// here; the MINE/CATALOG split earns its keep on the TAB, where you
    /// arrive fresh and want yours first.
    private var displayedSections: [FindOrCreateEngine.Section] {
        let sections = self.sections
        guard case .presented = mode, scope == .kit else { return sections }
        let flat = sections.flatMap(\.results).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !flat.isEmpty else { return [] }
        return [FindOrCreateEngine.Section(id: "ALL", title: "", count: flat.count, results: flat)]
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch mode {
            case .tab: tabBody
            case .presented: presentedBody
            case .picker: pickerBody
            }
        }
        .sheet(isPresented: $showingLibraryTray) {
            EquipmentLibraryTray()
        }
        .sheet(isPresented: $creatingExercise) {
            ExerciseEditorView(prefillName: trimmedQuery) { exercise in
                // The editor only INSERTS — save here so the id the landing
                // (or the pick) keys on is permanent, not the temporary one an
                // autosave would swap out from under it (swiftdata.md).
                try? modelContext.save()
                if let onPick {
                    // A picker's create goes STRAIGHT into what you were
                    // building — coming back to the picker to tap the row you
                    // just made is a step nobody wants.
                    onPick(exercise)
                } else {
                    ExerciseArrival.land(exercise.persistentModelID)
                }
            }
        }
        .alert("New routine", isPresented: $namingRoutine) {
            TextField("Name", text: $newRoutineName)
            Button("Create") { createRoutine(named: newRoutineName) }
            Button("Cancel", role: .cancel) { newRoutineName = "" }
        }
        .alert("New equipment", isPresented: $namingEquipment) {
            TextField("Name", text: $newEquipmentName)
            Button("Create") {
                let name = newEquipmentName.trimmingCharacters(in: .whitespaces)
                newEquipmentName = ""
                if !name.isEmpty { createEquipment(named: name.sentenceCasedFirst) }
            }
            Button("Cancel", role: .cancel) { newEquipmentName = "" }
        }
    }

    /// A tab root: its own stack, the tab-root header, and the bottom bar's
    /// field. Every value destination registers HERE, at the stack root (#262),
    /// so back returns to the results with query and scroll intact.
    private var tabBody: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(title: scope.label) {
                    // The kit is CONTEXT on every catalog, never a filter chip:
                    // it decides which rows fall into the "require more
                    // equipment" group below.
                    LibrarySwitcherKey(name: activeKitName, identifier: scope.switcherIdentifier) {
                        showingLibraryTray = true
                    }
                }
                listBody
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
            .navigationDestination(for: Equipment.self) { equipment in
                EquipmentDetailScreen(equipment: equipment)
            }
            .navigationDestination(for: RoutineRef.self) { ref in
                // Resolve from the stable uuid, never by pushing the @Model
                // (the tray-flicker law).
                if let routine = modelContext.routine(uuid: ref.uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $path) { routine in
                    routine.uuid.map { RoutineArrival.land($0) }
                }
            }
        }
        .revealRoot(tab: scope.tab.rawValue, atRoot: path.isEmpty)
        // The field's Return key reaches the ranked results through a
        // notification (it lives in the bar, outside every stack). All three
        // scopes are mounted, so only the one being looked at may answer.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOpenTopResult)) { _ in
            guard isActive else { return }
            openTopResult()
        }
        // A cross-tab add lands HERE with the entrance flash — consumed on
        // receive when mounted, on appear when this surface mounts because of
        // the add itself.
        .onReceive(NotificationCenter.default.publisher(for: scope.arrivalNotification)) { _ in
            consumeArrival()
        }
        .onAppear(perform: consumeArrival)
        // Operator's outcome navigation: a touched routine pushes by its stable
        // uuid. The path resets first, so the result is one Back from the list.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOperatorShow)) { note in
            guard scope == .routines,
                  let destination = note.object as? OperatorDestination,
                  case .routine(let uuid) = destination
            else { return }
            path = NavigationPath()
            path.append(RoutineRef(uuid: uuid))
        }
        // The bar's labels follow the query. `initial: true` seeds a surface
        // that mounts with a query already in hand.
        .onChange(of: trimmedQuery, initial: true) { _, _ in publishCount() }
    }

    /// The presented form (a sheet, or Today's setup push): pushed chrome with
    /// its own expanding field, an item destination, and — in setup mode — the
    /// pinned Done bar.
    private var presentedBody: some View {
        VStack(spacing: 0) {
            // Onboarding is a guided single-kit setup with its own Done bar; a
            // switch-kits control there is out of place. Everywhere else, name
            // the kit these adds land in.
            if !mode.setupMode { activeKitBar }
            listBody
        }
        .background(Theme.background)
        .pushedScreenChrome(
            title: presentedTitle,
            search: HeaderSearchConfig(
                text: $ownQuery,
                prompt: "Search \(scope.searchNoun)",
                identifier: "catalogSearchField"
            ),
            onBack: { dismiss() }
        )
        // Rightward row drags open the membership quick-add, so the full-width
        // back-swipe narrows to the edge band here — and hands full width back
        // the moment detail is pushed.
        .leadingRevealHost(active: pushed == nil)
        .navigationDestination(item: $pushed) { push in
            switch push {
            case .exercise(let exercise):
                ExerciseDetailScreen(exercise: exercise)
            case .equipment(let equipment):
                // Setup context strips the detail to add + configure: the
                // exercises/routines cross-links distract from the task.
                EquipmentDetailScreen(equipment: equipment, isOnboarding: mode.setupMode)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if mode.setupMode { setupDoneBar }
        }
        .onDisappear {
            // Plain back after engaging still counts as done.
            if mode.setupMode && touchedSetup && !SetupState.equipmentDone {
                SetupState.markEquipmentDone()
            }
        }
        // Membership changes + catalog adds reach GitHub when this closes.
        // (A tab root can't use this — it hides rather than unmounting, so the
        // root wires `syncsProgramOnHide` instead.)
        .syncsProgramOnClose()
    }

    /// The picker sheet: the same list, choosing instead of browsing, with the
    /// field at the BOTTOM (Dave, 2026-07-25) — where the app's own field is,
    /// and reachable from a sheet that came up from down there.
    private var pickerBody: some View {
        VStack(spacing: 0) {
            pickerHeader
            listBody
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SearchFieldBody(
                config: HeaderSearchConfig(
                    text: $ownQuery,
                    // What the scope SEARCHES, not what its tab is called.
                    prompt: "Search \(scope.searchNoun)",
                    identifier: "exercisePickerSearchField"
                ),
                wantsFocus: $pickerFieldWantsFocus
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            // OPAQUE, not a translucent `.bar` band: rows scroll under it and a
            // see-through strip would leave their text showing through the
            // field. (A tab root gets the scroll-edge effect for this; a sheet
            // has no scroll edge to hang it on.)
            .background(Theme.background)
        }
    }

    /// Mirrors the pushed catalogs' chrome (centered title flanked by keys) so
    /// the picker reads as one of the catalog family — with a text "Cancel"
    /// where a pushed screen has its back key. Dismissal is a WORD, never a ✕
    /// (✕ collapses search).
    private var pickerHeader: some View {
        ZStack {
            Text(pickerTitle)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 90)
            HStack(spacing: 10) {
                SheetDismissKey(label: "Cancel") { dismiss() }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var presentedTitle: String {
        switch scope {
        case .kit: return "Equipment catalog"
        case .exercises: return "Exercise catalog"
        case .routines: return "Routine catalog"
        }
    }

    /// Which kit these adds land in, named and switchable right here: this is
    /// the ADD surface, and a run of quick-adds could otherwise pour into the
    /// wrong kit unnoticed.
    private var activeKitBar: some View {
        HStack(spacing: 8) {
            Text(isBodyweightKit ? "On" : "Adding to")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
            LibrarySwitcherKey(name: activeKitName, identifier: "catalogKitSwitcher") {
                showingLibraryTray = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var setupDoneBar: some View {
        Button {
            touchedSetup = true
            SetupState.markEquipmentDone()
            dismiss()
        } label: {
            Text(kitNames.isEmpty ? "Done · bodyweight only" : "Done · \(kitNames.count) item\(kitNames.count == 1 ? "" : "s")")
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Theme.onPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
        .accessibilityIdentifier("setEquipmentButton")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - The list

    private var listBody: some View {
        // One relationship pass per render, shared by every equipment row's
        // "N exercises" capsule.
        let unlockedCounts = exerciseCountsByEquipment
        let collisions = self.collisions
        // HOISTED, and it matters: `sections` is a computed property that runs
        // the whole rank-and-group pipeline, and the body reads it twice (the
        // ForEach and the empty check). All three scopes stay mounted and share
        // the query, so an un-hoisted read is three extra full passes per
        // keystroke for lists nobody is looking at.
        let sections = displayedSections
        return ScrollViewReader { proxy in
            List {
                if showsCreateRow(collisions) {
                    createRow
                }
                if showsKitHint {
                    kitHint
                }
                // Real Sections (not loose header rows) so `.listStyle(.plain)`
                // PINS each heading until the next pushes it up. A `.missing`
                // section is the collapsible "require more equipment" group:
                // its rows show only when expanded, behind a plain header row.
                ForEach(sections) { section in
                    switch section.kind {
                    case .results:
                        Section {
                            ForEach(section.results) { result in
                                resultRow(result, unlockedCounts: unlockedCounts)
                            }
                            // Reorder is the routines tab's, and ONLY over your
                            // own doable ones with no query: a ranked or
                            // narrowed list has no order to write back.
                            .onMove(perform: moveHandler(for: section))
                        } header: {
                            sectionHeaderView(section)
                        }
                    case .missing(let noun):
                        Section {
                            MissingEquipmentHeaderRow(
                                count: section.count,
                                noun: noun,
                                isExpanded: expandedMissing.contains(section.id),
                                identifier: "missingEquipmentToggle-\(section.id)"
                            ) {
                                withAnimation(Theme.Anim.standard) {
                                    toggleMissing(section.id)
                                }
                            }
                            if expandedMissing.contains(section.id) {
                                ForEach(section.results) { result in
                                    resultRow(result, unlockedCounts: unlockedCounts)
                                }
                            }
                        }
                    }
                }
                if sections.isEmpty {
                    emptyState
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            // The arrival beat. Lifecycle-bound via `.task(id:)`: leaving or a
            // rapid second add cancels this in flight, and the throwing sleeps
            // bail in the catch WITHOUT clearing `newlyAdded`, so a superseding
            // add keeps its own highlight.
            .task(id: newlyAdded) {
                guard let target = newlyAdded else { return }
                do {
                    if scope == .routines {
                        // Beat of absence, so the eye sees the row OPEN rather
                        // than one that was already sitting there.
                        try await Task.sleep(for: .milliseconds(300))
                        withAnimation(Theme.Anim.flourish(.easeOut(duration: 0.3))) {
                            revealNewCard = true
                        }
                        try await Task.sleep(for: .milliseconds(60))
                        withAnimation(Theme.Anim.standard) {
                            proxy.scrollTo(AnyHashable(target), anchor: .top)
                        }
                        try await Task.sleep(for: .milliseconds(1600))
                    } else {
                        try await Task.sleep(for: .milliseconds(80))
                        withAnimation(Theme.Anim.standard) {
                            proxy.scrollTo(AnyHashable(target), anchor: .center)
                        }
                        try await Task.sleep(for: .seconds(2.2))
                    }
                } catch {
                    return
                }
                newlyAdded = nil
            }
        }
    }

    /// Only ever a genuinely empty match: with no query the whole scope shows,
    /// and un-doable items are grouped rather than hidden.
    private var emptyState: some View {
        Text("Nothing matches.")
            .font(.system(.footnote))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The Kit scope shows the whole equipment catalog, so its list can never
    /// be empty — but an empty MINE tier still deserves a word, and the null
    /// kit's explanation exists nowhere else.
    private var showsKitHint: Bool {
        scope == .kit && trimmedQuery.isEmpty && kitNames.isEmpty
    }

    private var kitHint: some View {
        Text(isBodyweightKit
             ? "Switch to another kit to add equipment. null is the no-equipment kit."
             : "Your kit is empty. Add equipment to unlock exercises and routines.")
            .font(.system(.footnote))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    private func toggleMissing(_ id: String) {
        if expandedMissing.contains(id) {
            expandedMissing.remove(id)
        } else {
            expandedMissing.insert(id)
        }
    }

    @ViewBuilder
    private func sectionHeaderView(_ section: FindOrCreateEngine.Section) -> some View {
        // An untitled section is the flat run (the presented equipment
        // catalog): no tiers, so nothing to head.
        if section.title.isEmpty {
            EmptyView()
        } else {
            SheetSectionLabel("\(section.title) · \(section.count)")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.horizontal, 16)
            // Full-bleed SOLID background: a pinned header floats over the rows
            // scrolling beneath it, so a clear fill would let their text show
            // through.
            .background(Theme.background)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .textCase(nil)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func resultRow(
        _ result: FindOrCreateEngine.Result,
        unlockedCounts: [PersistentIdentifier: Int]
    ) -> some View {
        Group {
            switch result.item {
            case .exercise(let exercise):
                exerciseRow(exercise, result: result)
            case .equipment(let equipment):
                equipmentRow(
                    equipment,
                    result: result,
                    unlocked: unlockedCounts[equipment.persistentModelID] ?? 0
                )
            case .routine(let routine):
                routineRow(routine, result: result)
            case .template(let template):
                templateRow(template, result: result)
            }
        }
        // NO context menu here, deliberately (2026-07-25). The universal-search
        // surface carried its quick acts on a long press because its rows had
        // no swipes; unified, the swipes ARE those acts (favorite, kit
        // membership, delete) and tap is Open, so the menu would only duplicate
        // them — and on the routines scope its long press would fight
        // `.onMove`'s, which is the same gesture. The one act that had no other
        // home here, "Start", lives on Today and on the routine's own screen.
        .overlay {
            // Both sides can be nil (a catalog template has no stored model and
            // nothing ever lands on it), so compare only real ids — `nil == nil`
            // would flash every template row at once.
            if let id = result.modelID, newlyAdded == id {
                RowEntranceFlash()
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
        // The arrival's authored beat: the row is held OUT of the list for
        // 300 ms, then fades in and pushes the rest down. Without this it
        // reads as a default List insert (the deleted RoutineCard carried it).
        .transition(.opacity)
    }

    private func exerciseRow(_ exercise: Exercise, result: FindOrCreateEngine.Result) -> some View {
        SwipeRevealRow(
            id: exercise.persistentModelID,
            openRow: $openSwipeRow,
            // Trailing DELETE only for customs; built-ins can't be deleted.
            actionsWidth: exercise.isBuiltIn ? 0 : 58,
            leadingActionsWidth: 58,
            onTap: { open(result) },
            accessibilityActions: exerciseActions(exercise)
        ) {
            // The modality figure says what KIND of movement this is, which is
            // information beyond "this row is an exercise".
            ExerciseRowContent(
                exercise: exercise,
                available: kitNames,
                // No chevron when picking: a tap SELECTS, it doesn't push.
                showsChevron: !isPicking,
                leadingSymbol: exercise.modalitySymbolName,
                nameHighlight: highlight(exercise.name)
            )
        } actions: {
            if !exercise.isBuiltIn {
                SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                    openSwipeRow = nil
                    modelContext.delete(exercise)
                }
            } else {
                EmptyView()
            }
        } leadingActions: {
            // Favorite is creation-of-yours → green; toggles off to a neutral
            // UNFAV when already lit. Unique per row: every realized row's
            // hidden action lives in the accessibility tree.
            SwipeActionButton(
                label: exercise.isFavorite ? "UNFAV" : "FAV",
                color: exercise.isFavorite ? Theme.textFaint : Theme.accent,
                identifier: "favSwipe-\(exercise.name)"
            ) {
                openSwipeRow = nil
                exercise.isFavorite.toggle()
            }
        }
    }

    private func equipmentRow(
        _ equipment: Equipment,
        result: FindOrCreateEngine.Result,
        unlocked: Int
    ) -> some View {
        let inKit = kitNames.contains(equipment.name)
        return SwipeRevealRow(
            id: equipment.persistentModelID,
            openRow: $openSwipeRow,
            actionsWidth: equipment.isBuiltIn ? 0 : 58,
            leadingActionsWidth: isBodyweightKit ? 0 : 58,
            onTap: { open(result) },
            accessibilityActions: equipmentActions(equipment, inKit: inKit)
        ) {
            EquipmentRowContent(
                equipment: equipment,
                unlockedCount: unlocked,
                inKit: inKit ? true : nil,
                nameHighlight: highlight(equipment.name)
            )
        } actions: {
            if !equipment.isBuiltIn {
                SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                    openSwipeRow = nil
                    deleteEquipment(equipment)
                }
            } else {
                EmptyView()
            }
        } leadingActions: {
            // Membership is the kit's curation. The null kit is immutable, so
            // it gets no swipe at all.
            if !isBodyweightKit {
                SwipeActionButton(
                    label: inKit ? "REMOVE" : "ADD",
                    color: inKit ? Theme.destructive : Theme.accent,
                    identifier: "quickAdd-\(equipment.name)"
                ) {
                    openSwipeRow = nil
                    setMembership(equipment, !inKit)
                }
            }
        }
        .accessibilityIdentifier("equipmentCard-\(equipment.name)")
    }

    private func routineRow(_ routine: Routine, result: FindOrCreateEngine.Result) -> some View {
        SwipeRevealRow(
            id: routine.persistentModelID,
            openRow: $openSwipeRow,
            actionsWidth: 58,
            onTap: { open(result) },
            accessibilityActions: [
                SwipeRowAction(name: "Delete") {
                    openSwipeRow = nil
                    deleteRoutine(routine)
                }
            ]
        ) {
            // The SHARED routine body (build 107's unification): title · one
            // meta line · the gear tier. Cardless out here, but a routine still
            // has to say its schedule, focus, effort and estimate — the row
            // lost the card, not its facts.
            RoutineCardContent(
                title: routine.name,
                meta: RoutineMeta(routine: routine, activeNames: kitNames),
                nameHighlight: highlight(routine.name),
                leadingCapsules: matchCapsules(result.matchedExerciseName)
            )
        } actions: {
            SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                openSwipeRow = nil
                deleteRoutine(routine)
            }
        }
    }

    /// A catalog template: nothing of yours to curate or destroy, so it's a
    /// plain row. Adding it is the context menu (or its detail screen).
    private func templateRow(_ template: RoutineTemplate, result: FindOrCreateEngine.Result) -> some View {
        Button {
            open(result)
        } label: {
            // Same body as a routine's, so a template reads identically to what
            // it becomes — the number must not visibly change the moment you
            // add it (the estimate mirrors `Routine.estimatedSeconds`).
            RoutineCardContent(
                title: template.name,
                meta: RoutineMeta(
                    focus: template.focus.rawValue,
                    effort: template.effort.rawValue,
                    estimate: template.estimatedMinutesText,
                    gear: template.equipmentNames.map { (name: $0, available: kitNames.contains($0)) }
                ),
                nameHighlight: highlight(template.name),
                leadingCapsules: matchCapsules(result.matchedExerciseName)
            )
        }
        .buttonStyle(.plain)
    }

    private func exerciseActions(_ exercise: Exercise) -> [SwipeRowAction] {
        var actions = [SwipeRowAction(name: exercise.isFavorite ? "Unfavorite" : "Favorite") {
            openSwipeRow = nil
            exercise.isFavorite.toggle()
        }]
        if !exercise.isBuiltIn {
            actions.append(SwipeRowAction(name: "Delete") {
                openSwipeRow = nil
                modelContext.delete(exercise)
            })
        }
        return actions
    }

    private func equipmentActions(_ equipment: Equipment, inKit: Bool) -> [SwipeRowAction] {
        var actions: [SwipeRowAction] = []
        if !isBodyweightKit {
            actions.append(SwipeRowAction(name: inKit ? "Remove from kit" : "Add to kit") {
                openSwipeRow = nil
                setMembership(equipment, !inKit)
            })
        }
        if !equipment.isBuiltIn {
            actions.append(SwipeRowAction(name: "Delete") {
                openSwipeRow = nil
                deleteEquipment(equipment)
            })
        }
        return actions
    }

    /// The "has X" explainer, when a routine matched the query through a move
    /// it CONTAINS rather than through its own name — otherwise the row's name
    /// says nothing about what was typed.
    private func matchCapsules(_ matched: String?) -> [CardCapsule] {
        matched.map { [CardCapsule(text: "has \($0)")] } ?? []
    }

    private func highlight(_ name: String) -> [Range<String.Index>] {
        guard !trimmedQuery.isEmpty else { return [] }
        return FuzzySearch.highlightRanges(query: trimmedQuery, in: name)
    }

    /// One relationship pass per render (the equipment catalog's index
    /// pattern) so every equipment row's "N exercises" capsule doesn't rescan.
    private var exerciseCountsByEquipment: [PersistentIdentifier: Int] {
        guard scope == .kit else { return [:] }
        var unlocked: [PersistentIdentifier: Int] = [:]
        for exercise in allExercises {
            for gear in exercise.equipment where !gear.isDeleted {
                unlocked[gear.persistentModelID, default: 0] += 1
            }
        }
        return unlocked
    }

    // MARK: - Opening

    private func open(_ result: FindOrCreateEngine.Result) {
        touchedSetup = true
        // A row tap only ever fires from the ROOT, and `path.append` is not
        // idempotent (ui-interaction.md) — a second tap landing during the push
        // animation would stack a duplicate screen behind the first.
        guard onPick != nil || !mode.isTab || path.isEmpty else { return }
        switch result.item {
        case .exercise(let exercise):
            // Picking hands the item back; the caller decides what happens to
            // it (a routine add, a swap, a configure sheet stacked on this one).
            if let onPick { onPick(exercise); return }
            if mode.isTab { path.append(exercise) } else { pushed = .exercise(exercise) }
        case .equipment(let equipment):
            if mode.isTab { path.append(equipment) } else { pushed = .equipment(equipment) }
        case .routine(let routine):
            // The routine family pushes by uuid, never the model.
            guard mode.isTab else { return unroutableInPresentedMode() }
            routine.uuid.map { path.append(RoutineRef(uuid: $0)) }
        case .template(let template):
            guard mode.isTab else { return unroutableInPresentedMode() }
            path.append(template)
        }
    }

    /// A presented catalog has no stack of its own to push a routine onto — it
    /// pushes with an item destination that carries only exercises and
    /// equipment. Every caller today presents `.kit`, so this is unreachable;
    /// it exists loud rather than silent because the failure mode otherwise is
    /// the build-76 one — rows that render, chevrons that render, taps that do
    /// nothing, and no compile error anywhere.
    private func unroutableInPresentedMode() {
        assertionFailure("\(scope) can't be opened from a presented catalog — extend Push first")
    }

    /// Return opens the best hit — the first row of the first section.
    /// Root-only: the field lives in the bottom BAR, outside this stack, so it
    /// stays submittable over a pushed detail, and `path.append` is not
    /// idempotent (ui-interaction.md).
    private func openTopResult() {
        guard path.isEmpty, let top = sections.first?.results.first else { return }
        open(top)
    }

    // MARK: - Create

    /// Exact-name collisions for the live query — a create is dropped when its
    /// type would duplicate an item that already exists under that name.
    private var collisions: FindOrCreateEngine.Collisions {
        FindOrCreateEngine.collisions(
            query: trimmedQuery,
            exercises: allExercises,
            equipment: allEquipment,
            routines: routines,
            templates: RoutineCatalog.all
        )
    }

    private func showsCreateRow(_ collisions: FindOrCreateEngine.Collisions) -> Bool {
        switch scope {
        case .routines: return !collisions.routine
        case .exercises: return !collisions.exercise
        case .kit: return !collisions.equipment
        }
    }

    @ViewBuilder
    private var createRow: some View {
        Group {
            switch scope {
            case .routines:
                CreateRow(label: routinesCreateLabel, identifier: "newRoutineButton") {
                    createRoutineFromQuery()
                }
            case .exercises:
                // The picker keeps its own id — the smoke flows create a custom
                // exercise from inside a routine through it.
                CreateRow(
                    label: exercisesCreateLabel,
                    identifier: isPicking ? "newExerciseButton" : "createExerciseRow"
                ) {
                    creatingExercise = true
                }
            case .kit:
                CreateRow(label: kitCreateLabel, identifier: "addEquipmentRow") {
                    createEquipmentFromQuery()
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
    }

    private var quotedQuery: String {
        "\u{201C}\(trimmedQuery.sentenceCasedFirst)\u{201D}"
    }

    private var routinesCreateLabel: String {
        trimmedQuery.isEmpty ? "New routine" : "New routine \(quotedQuery)"
    }

    private var exercisesCreateLabel: String {
        trimmedQuery.isEmpty ? "New exercise" : "Create \(quotedQuery)"
    }

    private var kitCreateLabel: String {
        trimmedQuery.isEmpty ? "New equipment" : "Add \(quotedQuery) as equipment"
    }

    /// A queried create is direct — the query IS the name; an empty one asks
    /// for a name first, never minting junk "New Routine" rows.
    private func createRoutineFromQuery() {
        if trimmedQuery.isEmpty {
            newRoutineName = ""
            namingRoutine = true
        } else {
            createRoutine(named: trimmedQuery.sentenceCasedFirst)
        }
    }

    private func createRoutine(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        newRoutineName = ""
        guard !trimmed.isEmpty else { return }
        let routine = Routine(name: Routine.uniqueName(trimmed, among: routines), order: 0)
        modelContext.insert(routine)
        for existing in routines where existing !== routine {
            existing.order += 1
        }
        // Synchronous save: permanent ids before any presentation keys on them,
        // and the landing resolves by uuid (swiftdata.md).
        try? modelContext.save()
        routine.uuid.map { RoutineArrival.land($0) }
    }

    private func createEquipmentFromQuery() {
        // The null kit is immutable (setMembership no-ops), so an unguarded
        // create would land on its empty list and read as data loss. Adding
        // means switching first: open the tray, which explains and offers it.
        guard !isBodyweightKit else {
            showingLibraryTray = true
            return
        }
        let name = trimmedQuery.sentenceCasedFirst
        guard !name.isEmpty else {
            newEquipmentName = ""
            namingEquipment = true
            return
        }
        createEquipment(named: name)
    }

    /// Dedupe on the lowercased name (typing "barbell" over an existing Barbell
    /// just adds it to the kit), insert if new, join the active kit, save
    /// synchronously, then land — or, on a presented catalog, push its detail
    /// so it can be configured right away.
    private func createEquipment(named name: String) {
        let item: Equipment
        if let existing = allEquipment.first(where: { $0.name.lowercased() == name.lowercased() }) {
            item = existing
        } else {
            let created = Equipment(name: name, isBuiltIn: false)
            modelContext.insert(created)
            item = created
        }
        activeLibrary?.setMembership(item, true)
        touchedSetup = true
        try? modelContext.save()
        if mode.isTab {
            EquipmentArrival.land(item.persistentModelID)
        } else {
            pushed = .equipment(item)
        }
    }

    // Adding a catalog template happens on its own screen (one tap in from its
    // row), which owns the double-fire guard and lands the result here.

    // MARK: - Mutations

    private func setMembership(_ equipment: Equipment, _ included: Bool) {
        activeLibrary?.setMembership(equipment, included)
        touchedSetup = true
        try? modelContext.save()
    }

    private func deleteEquipment(_ equipment: Equipment) {
        // Belt-and-braces since #196 gave the relationship an explicit inverse:
        // stripping references first keeps deletion order-independent (B1).
        for exercise in allExercises {
            exercise.equipment.removeAll { $0 === equipment }
        }
        modelContext.delete(equipment)
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        for (index, existing) in routines.enumerated() {
            existing.order = index
        }
    }

    // MARK: - Reorder

    /// Drag-reorder belongs to your own routines, in the list you actually
    /// sequence: the routines scope, on a tab, with no query narrowing or
    /// ranking the rows, over the MINE tier's doable group.
    private func moveHandler(for section: FindOrCreateEngine.Section) -> ((IndexSet, Int) -> Void)? {
        let reorderable = scope == .routines
            && mode.isTab
            && trimmedQuery.isEmpty
            && section.id == "MINE"
        return reorderable ? moveRoutines : nil
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        guard let section = sections.first(where: { $0.id == "MINE" && $0.kind == .results }) else { return }
        var reordered = section.results.compactMap { result -> Routine? in
            if case .routine(let routine) = result.item { return routine }
            return nil
        }
        reordered.move(fromOffsets: source, toOffset: destination)
        // Write `order` back over the WHOLE list as (reordered) ++ (the rest,
        // order preserved) so `order` stays a clean 0..n and a kit change
        // re-sorts cleanly. The missing group is pushed to a contiguous
        // trailing block — order is one sequence, split only for display.
        let moved = Set(reordered.map(\.persistentModelID))
        let rest = routines.filter { !moved.contains($0.persistentModelID) }
        for (index, routine) in (reordered + rest).enumerated() {
            routine.order = index
        }
    }

    // MARK: - Arrivals + counts

    /// Land a cross-tab add: pop to the list, reveal whatever would hide the
    /// new row, and arm the scroll + flash.
    private func consumeArrival() {
        guard mode.isTab else { return }
        switch scope {
        case .routines:
            // The slot clears BEFORE resolution — every landing path saves
            // before posting, so a miss means a stale routine, and holding the
            // slot would fire a phantom path-reset on some later visit.
            guard let uuid = RoutineArrival.pending else { return }
            RoutineArrival.pending = nil
            guard let routine = modelContext.routine(uuid: uuid) else { return }
            path = NavigationPath()
            revealNewCard = false      // hold the row out for the entrance beat
            if !routine.gearAvailability(activeNames: kitNames).allSatisfy(\.available) {
                expandMissingGroups()
            }
            newlyAdded = routine.persistentModelID
        case .exercises:
            guard let pending = ExerciseArrival.pending else { return }
            ExerciseArrival.pending = nil
            path = NavigationPath()
            expandMissingGroups()
            newlyAdded = pending
        case .kit:
            guard let pending = EquipmentArrival.pending else { return }
            EquipmentArrival.pending = nil
            path = NavigationPath()
            newlyAdded = pending
        }
    }

    /// A landed item that needs gear sits in a collapsed group; open both tiers
    /// so its entrance flash isn't playing on a hidden row.
    private func expandMissingGroups() {
        expandedMissing = ["MISSING_MINE", "MISSING_CATALOG"]
    }

    private func publishCount() {
        guard mode.isTab else { return }
        // No query counts nothing, so the labels stay bare until there's
        // something to count.
        counts[scope] = trimmedQuery.isEmpty ? nil : sections.reduce(0) { $0 + $1.count }
    }
}

private extension FindScope {
    /// Distinct per surface so a smoke test visiting more than one doesn't hit
    /// a multiple-match on a shared identifier.
    var switcherIdentifier: String {
        switch self {
        case .routines: return "routinesKitSwitcher"
        case .exercises: return "exercisesKitSwitcher"
        case .kit: return "librarySwitcherButton"
        }
    }

    /// The landing this scope answers — one landing for every add.
    var arrivalNotification: Notification.Name {
        switch self {
        case .routines: return .plusplusRoutineArrived
        case .exercises: return .plusplusExerciseArrived
        case .kit: return .plusplusEquipmentArrived
        }
    }
}

private extension FindOrCreateEngine.Result {
    /// The stored model behind this row, when there is one — a catalog template
    /// has none, and nothing lands on it.
    var modelID: PersistentIdentifier? {
        switch item {
        case .exercise(let exercise): return exercise.persistentModelID
        case .equipment(let equipment): return equipment.persistentModelID
        case .routine(let routine): return routine.persistentModelID
        case .template: return nil
        }
    }
}


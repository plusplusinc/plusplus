import SwiftUI
import SwiftData
import PlusPlusKit

/// ONE view per catalog type (Dave, 2026-07-25): searching a catalog and
/// browsing it are the same screen, because search only adds a QUERY. That is
/// the whole point of this file — the universal-search surface had become a
/// second copy of the three catalog tabs, so the two became one. As of
/// 2026-08-02 there is no separate search surface left at all: the query
/// arrives from the SYSTEM's own bottom search field, minimized to a key.
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
        /// A tab root: owns a `NavigationStack` and the app's expanding header
        /// search field. `query` still arrives as a binding, because the scope
        /// picker that outlives this view lives in the tab bar's accessory.
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

    /// The query. In `.tab` mode it lives in the ROOT — one query shared by all
    /// three catalogs, so switching tabs mid-search keeps what you typed; in
    /// `.presented` mode the surface owns it.
    @Binding private var boundQuery: String
    /// Whether the floating search field is open. Root-owned in `.tab` mode for
    /// the same reason the query is: three tabs are three live instances of
    /// this view, and search is one thing.
    @Binding private var searchOpen: Bool
    // Per-scope match COUNTS are gone with the hand-drawn bar (2026-07-25):
    // there are no scope labels in the chrome to paint them on. The segmented
    // picker in the tab bar's accessory is the cross-scope affordance now.
    /// Which tab root this is: the reveal drawer's per-tab swipe gate keys on
    /// it, and so does `ownsLandings`.
    ///
    /// That second job is load-bearing since the catalogs became tabs again
    /// (2026-07-26): a `Tab`'s content is its own view tree, so the three
    /// catalog tabs are three live instances of this view. Anything answering a
    /// broadcast has to name one of them.
    private let tabKey: String
    /// Picker mode only: a row tap (or a fresh create) hands the item back
    /// here instead of opening it.
    private let onPick: ((Exercise) -> Void)?
    /// Picker mode's sheet title ("Add exercise" / "Swap for…").
    private var pickerTitle = ""

    /// A tab root: its own stack, the system bar, and the floating search dock.
    init(
        scope: FindScope,
        query: Binding<String>,
        searchOpen: Binding<Bool>,
        tab: AppTab
    ) {
        self.scope = scope
        self.mode = .tab
        self._boundQuery = query
        self._searchOpen = searchOpen
        self.tabKey = tab.rawValue
        self.onPick = nil
    }

    /// A presented catalog (the pushed equipment catalog's replacement).
    init(scope: FindScope, setupMode: Bool = false) {
        self.scope = scope
        self.mode = .presented(setupMode: setupMode)
        self._boundQuery = .constant("")
        self._searchOpen = .constant(false)
        self.tabKey = ""
        self.onPick = nil
    }

    /// A picker sheet: the same catalog, but choosing rather than browsing.
    init(picking scope: FindScope, title: String, onPick: @escaping (Exercise) -> Void) {
        self.scope = scope
        self.mode = .picker
        self._boundQuery = .constant("")
        self._searchOpen = .constant(false)
        self.tabKey = ""
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
    /// Observed, not read through `SetupState` (review): a plain UserDefaults
    /// read in a body is stale the moment anything writes it while the screen
    /// is up, with nothing to invalidate the render. `RootTabView` already
    /// binds this key the same way.
    @AppStorage(SetupState.equipmentDoneKey) private var equipmentStepDone = false

    /// The presented and picker forms' own query (unused in `.tab` mode, where
    /// the field is the bottom bar's and the query lives in the root).
    @State private var ownQuery = ""
    /// The picker field's one-shot focus intent. Never armed on entry — the
    /// list is the point; the keyboard rises when the field is tapped.
    @State private var pickerFieldWantsFocus = false
    @State private var path = NavigationPath()
    @State private var pushed: Push?
    // No `openSwipeRow` here any more: the catalog rows use NATIVE
    // `.swipeActions` (2026-07-27), so UIKit owns which row is open, how it
    // closes, and — the point of the change — the arbitration with the scroll
    // pan. `SwipeRevealRow` survives only where a row is not in a `List`.
    /// Which "N … require more equipment" groups are open, by `Section.id`
    /// ("MISSING_MINE" / "MISSING_CATALOG"). Collapsed by default.
    @State private var expandedMissing: Set<String> = []
    @State private var showingLibraryTray = false
    /// Set only when the tray opens as a REDIRECT (#507, b9); cleared on
    /// every other route in so a later deliberate open never inherits a
    /// stale explanation.
    @State private var libraryTrayReason: String?
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
    /// The facet row's state (filtering returns, 2026-07-31): one value
    /// struct per surface INSTANCE, never persisted. Each tab owns its own,
    /// so switching catalogs cannot carry invisible narrowing across; the
    /// summary chip keeps surviving state announced within a tab.
    @State private var filters = CatalogFilterState()

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
    /// GENUINE first-run, not merely "presented with the guided Done bar"
    /// (#508, b13). `setupMode` had two effects wired together: the Done-bar
    /// chrome, and stripping equipment detail down to add-and-configure by
    /// hiding its EXERCISES/ROUTINES graph. The drawer's "Edit your kit"
    /// passes the flag for the CHROME, so it lost the graph too — most
    /// useful exactly when curating an established kit, which is the only
    /// time you reach that entry. Once the equipment step is done, setup is
    /// over by definition, so the graph comes back and the chrome stays.
    private var isFirstRunSetup: Bool { mode.setupMode && !equipmentStepDone }

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

    /// The scope's whole answer for the live query: sections to draw, and
    /// how many matches the active facets are holding back. ONE pass —
    /// the engine counts the hidden rows where it already examines them,
    /// so both the "N hidden by filters" key and the summary popover's
    /// "N of M shown" come free (#507).
    ///
    /// ⚠️ The alternative was `unfilteredCount() - shown`, and the trap
    /// is that it looks cheap: the old `unfilteredCount()` really was a
    /// second full ranking pass, but it was a CLOSURE the popover fired
    /// on OPEN, so it cost nothing while you typed. Reading it from a
    /// row in the list would have moved that pass into the render path —
    /// per keystroke, for a list nobody had asked a question about. The
    /// number being always-in-hand is also why the chip's `total` stops
    /// being a closure: there is nothing left to defer.
    private var outcome: FindOrCreateEngine.Outcome {
        FindOrCreateEngine.outcome(
            query: trimmedQuery,
            scope: scope,
            filters: filters,
            exercises: allExercises,
            equipment: allEquipment,
            routines: displayedRoutines,
            templates: RoutineCatalog.all,
            kitNames: kitNames
        )
    }

    /// For actions, which run once and can afford their own pass.
    private var sections: [FindOrCreateEngine.Section] { outcome.sections }

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
    private func displayed(_ sections: [FindOrCreateEngine.Section]) -> [FindOrCreateEngine.Section] {
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
            case .tab: tabStack
            case .presented: presentedBody
            case .picker: pickerBody
            }
        }
        .sheet(isPresented: $showingLibraryTray) {
            EquipmentLibraryTray(reason: libraryTrayReason)
        }
        .sheet(isPresented: $creatingExercise) {
            // The muscle facet prefills the create (#507, b8): the
            // editor's `prefillMuscleGroup` had existed with ZERO call
            // sites, so a create under an active Chest→Back filter still
            // defaulted to Chest and landed outside the very facet you
            // were browsing. ⚠️ Only the muscle chip threads, and the
            // others deliberately do not: ONE selected muscle is an
            // intent worth prefilling, while several is a browse and
            // picking one of them would be a guess (#498), and the
            // attribute facets (#496) would be guessing outright — a
            // fresh custom has no pattern until its owner gives it one.
            // The landing covers both: `clearFiltersHiding` drops any
            // facet the new row fails, so it is never flashed off-list.
            ExerciseEditorView(prefillName: trimmedQuery,
                               prefillMuscleGroup: filters.muscles.count == 1 ? filters.muscles.first : nil) { exercise in
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

    /// A tab root: its own stack, the SYSTEM navigation bar, and the floating
    /// search dock. Every value destination registers HERE, at the stack root
    /// (#262), so back returns to the results with query and scroll intact.
    ///
    /// **The hand-drawn `CatalogTabHeader` is gone** (Dave, 2026-07-26: "fuck
    /// it, let's kill our custom header"). The app hid the navigation bar on
    /// every tab root and drew its own title row; the title, the ++ key and the
    /// kit switcher moved into the real bar and nothing was lost but the
    /// hand-drawing. ⚠️ A tab root still must not hide that bar — the reasons
    /// have changed but the rule has not: it carries the large title, both keys,
    /// and the Dynamic-Type reflow the old hand rules policed by hand.
    ///
    /// ⚠️ The `GeometryReader` that used to wrap this is GONE with the search
    /// tab (2026-08-02). It existed to measure the bar for the hand-laid
    /// `.principal` scope row, and it was a pure read specifically to stay
    /// clear of the morph law. All three catalogs now take the same ordinary
    /// path, so nothing here measures anything.
    private var tabStack: some View {
        NavigationStack(path: $path) {
            listBody
                .background(Theme.background)
                .navigationTitle(scope.label)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    // ⚠️ ONE chrome for all three catalogs now (2026-08-02).
                    // The search tab used to build this row BY HAND as a single
                    // `.principal` item — a title view UIKit centres in the BAR
                    // rather than between the side items, so any side item made
                    // the two gaps differ by its own width (measured build 150:
                    // a 42 pt ++ key against a 78 pt kit switcher gave 76 pt of
                    // gap on the left and 40 pt on the right, and
                    // `.frame(maxWidth: .infinity)` could not fix it because the
                    // bar proposes an unbounded width). That row existed only to
                    // seat the segmented scope control. The control is gone with
                    // the search tab, so the row is too, and the system places
                    // these two the way it does on every other root.
                    ToolbarItem(placement: .topBarLeading) { AppMenuKey() }
                    // The kit is CONTEXT on every catalog, never a filter
                    // chip: it decides which rows fall into the "require
                    // more equipment" group below.
                    ToolbarItem(placement: .topBarTrailing) {
                        LibrarySwitcherKey(name: activeKitName, identifier: scope.switcherIdentifier, chrome: .toolbar) {
                            libraryTrayReason = nil
                            showingLibraryTray = true
                        }
                    }
                }
                // ⚠️ THE NATIVE SEARCH UI (spike, 2026-08-02). `.searchable`
                // on a view INSIDE the stack, then `.searchToolbarBehavior`
                // AFTER it — Apple's documented order ("place this modifier
                // after the searchable modifier that renders search in the
                // toolbar"). On iPhone iOS 26 that yields a bottom-toolbar
                // search field which `.minimize` renders as a button-like
                // control when inactive: the floating search key, system-owned.
                //
                // ⚠️ It is `.minimize`, NOT `.minimized`. Apple's own Discussion
                // sample writes `.minimized`, which does not exist — the
                // declared type property on `SearchToolbarBehavior` is
                // `minimize`. The declaration wins over the prose.
                //
                // `isPresented` is bound so open/closed still SURVIVES a tab
                // switch and a trip to Today, which is the behaviour Dave
                // chose; the query binding is unchanged, so one query still
                // serves all three catalogs.
                .searchable(
                    text: $boundQuery,
                    isPresented: $searchOpen,
                    prompt: "Search \(scope.searchNoun)"
                )
                .searchToolbarBehavior(.minimize)
                // Keeps the ++ key and the kit switcher while search is active
                // — without it the system clears the bar to make room, which is
                // the build-143 emptying. Still load-bearing.
                .searchPresentationToolbarBehavior(.avoidHidingContent)
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
                        // Pop the template BEFORE landing. The landing happens
                        // on the Routines tab, which may be a different
                        // instance of this view (search pushed it, the tab
                        // consumes it), and whoever hosted the push would
                        // otherwise keep a stale detail of a template you had
                        // already added.
                        path = NavigationPath()
                        routine.uuid.map { RoutineArrival.land($0) }
                    }
                }
        }
        .revealRoot(tab: tabKey, atRoot: path.isEmpty)
        // Leaving the catalog is the boundary that pushes program edits to
        // GitHub. Native tabs fire `onDisappear` on a switch, so this is the
        // same close trigger every other surface uses.
        .syncsProgramOnClose()
        // ⚠️ The `.onChange(of: scope)` reset is GONE with the search tab
        // (2026-08-02). It existed because ONE instance changed scope under
        // you — search dialling its segmented control — and had to drop the
        // pushed detail, the opened groups and the facets that belonged to the
        // old catalog. Every instance's `scope` is a per-tab LITERAL now, so it
        // never changes and the handler could never fire; each tab keeps its
        // own path, groups and facets for as long as it lives, which is what a
        // tab is meant to do.
        // A cross-tab add lands HERE with the entrance flash — consumed on
        // receive when this tab is already built, on appear when the landing is
        // what brought it forward.
        .onReceive(NotificationCenter.default.publisher(for: scope.arrivalNotification)) { _ in
            consumeArrival()
        }
        .onAppear {
            consumeArrival()
            consumeOperatorPush()
        }
        // Operator's outcome navigation: a touched routine pushes by its stable
        // uuid. Same two-door handoff as an arrival — the tab this lands on may
        // not have been built yet when the notification goes out.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOperatorShow)) { _ in
            consumeOperatorPush()
        }
    }

    /// Whether landings addressed to this scope belong to THIS instance.
    ///
    /// ⚠️ Read it for what it now IS: `mode.isTab`, written obliquely. Every
    /// tab instance passes a matching `tabKey`/`scope` pair, so this is `true`
    /// on all three and `false` only for presented/picker forms, whose `tabKey`
    /// is `""` — i.e. **presented and picker surfaces do not consume arrivals**.
    /// It earned its original phrasing when a search tab dialled to routines
    /// was a SECOND live instance showing the same rows; if a second instance
    /// of one scope ever returns, this needs to become a real test again rather
    /// than inheriting the guarantee. The SLOT mechanism behind it is unchanged
    /// and still load-bearing: both slots survive an unbuilt tab, so the owner
    /// can consume late, on appear.
    private var ownsLandings: Bool { tabKey == scope.tab.rawValue }

    /// Push the routine an Operator outcome is steering to. The path resets
    /// first, so the result is one Back from the list.
    private func consumeOperatorPush() {
        guard ownsLandings, scope == .routines, let uuid = OperatorArrival.takeRoutine() else { return }
        path = NavigationPath()
        path.append(RoutineRef(uuid: uuid))
    }

    /// The presented form (a sheet, or Today's setup push): pushed chrome with
    /// its own expanding field, an item destination, and — in setup mode — the
    /// pinned Done bar.
    private var presentedBody: some View {
        VStack(spacing: 0) {
            // Onboarding is a guided single-kit setup with its own Done bar; a
            // switch-kits control there is out of place. Everywhere else, name
            // the kit these adds land in.
            // Keyed on FIRST RUN, not on the chrome flag (#508, b13 +
            // review): "adds land in ⟨kit⟩" is exactly what someone curating
            // an established kit needs, and it was hidden for the same
            // reason the graph was.
            if !isFirstRunSetup { activeKitBar }
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
        // ⚠️ STILL REQUIRED after the move to native `.swipeActions`. The
        // leading edge is the membership quick-add, and the app's own
        // full-width pop pan declares `shouldRecognizeSimultaneouslyWith` false
        // — so it would win every rightward drag from UIKit's cell swipe just
        // as it did from the hand-rolled one. Narrow the back-swipe to the edge
        // band here, and hand full width back the moment detail is pushed.
        .leadingRevealHost(active: pushed == nil)
        .navigationDestination(item: $pushed) { push in
            switch push {
            case .exercise(let exercise):
                ExerciseDetailScreen(exercise: exercise)
            case .equipment(let equipment):
                // Setup context strips the detail to add + configure: the
                // exercises/routines cross-links distract from the task.
                EquipmentDetailScreen(equipment: equipment, isOnboarding: isFirstRunSetup)
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
        NavigationStack {
        VStack(spacing: 0) {
            listBody
        }
        .background(Theme.background)
        // Cancel was ALREADY on the left here (the picker mirrored a pushed
        // screen's back key), so this is the one sheet whose keys do not move.
        // Picking a row is the action; leaving without one is a cancel.
        .sheetChrome(title: pickerTitle, cancel: SheetAction("Cancel") { dismiss() })
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
                libraryTrayReason = nil
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
            // ⚠️ Guarded, like the onDisappear path above (review):
            // `markEquipmentDone` rewrites the completion DATE, so an
            // established user tapping Done from the drawer's "Edit your
            // kit" moved their setup milestone's date to today. Setup is
            // finished once; finishing it again is not an event.
            if !equipmentStepDone { SetupState.markEquipmentDone() }
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
        // OPAQUE, not a translucent `.bar` band — the same rule the picker's
        // bottom field states above, and for the same reason: rows scroll under
        // this and a see-through strip leaves their text showing through the
        // key. This is a PRESENTED surface, so there's no scroll edge to hang
        // the effect on. (Missed when that rule was written;
        // liquid-glass-auditor caught it.)
        .background(Theme.background)
    }

    // MARK: - The list

    private var listBody: some View {
        // One relationship pass per render, shared by every equipment row's
        // "N exercises" capsule.
        let unlockedCounts = exerciseCountsByEquipment
        let collisions = self.collisions
        // HOISTED, and it matters: `outcome` is a computed property that runs
        // the whole rank-and-group pipeline, and the body reads its sections
        // twice (the ForEach and the empty check). All three scopes stay
        // mounted and share the query, so an un-hoisted read is three extra
        // full passes per keystroke for lists nobody is looking at.
        let outcome = self.outcome
        let sections = displayed(outcome.sections)
        let shown = sections.reduce(0) { $0 + $1.count }
        let hiddenByFilters = outcome.hiddenByFilters
        return ScrollViewReader { proxy in
            List {
                // ONE section holds the whole list, and on a TAB root its
                // HEADER is the facet row — which is what makes the chips
                // stick (Dave, 2026-08-01 device pass: "the filter menu
                // triggers … aren't sticky, they're scrolling out the top
                // of the viewport"). `.listStyle(.plain)` pins the current
                // section's header, so a header over ALL the rows pins for
                // the whole scroll.
                //
                // ⚠️ This is the THIRD mount, and the other two are both
                // ruled out — do not re-try either. A pinned top
                // `safeAreaInset` (#494) broke the system large-title bar
                // on tab roots: no title at rest, a title-sized dead band,
                // a hairline in both states (measured off Dave's
                // screenshots, #521). First-list-CONTENT (#521's fix) kept
                // the title honest, but the chips then scrolled away with
                // the list — which is the complaint this note answers.
                // A section header is inside the list's own layout, so it
                // touches neither the safe area nor the nav bar: the title
                // behaves and the chips stay put.
                //
                // ⚠️ The cost, accepted: the MINE/CATALOG tier labels stop
                // pinning (they are plain rows now). Only one header can
                // pin at a time, and the facet row has to outlive the tier
                // boundaries or it isn't sticky — a tier label is a
                // divider you read once, the chips are a control you reach
                // for at any depth.
                Section {
                    // ⚠️ ABOVE the create row, and a plain row — not a
                    // second pinned header (#507): the facet row is this
                    // list's ONE header, and only one can pin. The
                    // create row is the easy path to a near-duplicate,
                    // so what the filters are HIDING has to be read
                    // before it, not after.
                    if !trimmedQuery.isEmpty, hiddenByFilters > 0 {
                        hiddenByFiltersRow(hiddenByFilters)
                    }
                    if showsCreateRow(collisions) {
                        createRow
                    }
                    if showsKitHint {
                        kitHint
                    }
                    ForEach(sections) { section in
                        switch section.kind {
                        case .results:
                            tierLabelRow(section)
                            ForEach(section.results) { result in
                                resultRow(result, unlockedCounts: unlockedCounts)
                            }
                            // Reorder is the routines tab's, and ONLY over your
                            // own doable ones with no query: a ranked or
                            // narrowed list has no order to write back.
                            .onMove(perform: moveHandler(for: section))
                        case .missing(let noun):
                            // The collapsible "require more equipment" group:
                            // its rows show only when expanded, behind a
                            // plain (never pinned) header row.
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
                        case .unrated:
                            // Hand-built routines under an Effort/Style
                            // facet (#507, Q14-A) — the same collapsible
                            // shape as the missing-equipment group, and
                            // the same law: narrowed, never vanished.
                            MissingEquipmentHeaderRow(
                                count: section.count,
                                noun: "routine",
                                isExpanded: expandedMissing.contains(section.id),
                                identifier: "unratedToggle",
                                sentence: UnratedPhrasing.line(count: section.count)
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
                    if sections.isEmpty {
                        emptyState(hiddenByFilters: hiddenByFilters)
                    }
                } header: {
                    if mode.isTab {
                        filterRow(shown: shown, hidden: hiddenByFilters)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            // ⚠️ NO `.listSectionSpacing(.custom(0))` / `.contentMargins(.top, 0)`
            // here any more (2026-08-02). That pair seated the facet row against
            // the bar from rest, and it was SEARCH-ONLY: on a surface with no
            // large title, a `.plain` List's scrolling top padding left the row
            // ~22 pt low and blinked the bar's scrolled-under hairline for
            // exactly that window. All three catalogs wear the system LARGE
            // title now, and that title travels through this very space —
            // closing it here would seat the chips against the bar and re-open
            // the #521 class of large-title argument.
            .scrollContentBackground(.hidden)
            // ⚠️ LOAD-BEARING since the search tab died (2026-08-02), not
            // merely conformant. The floating field lives above the tab bar and
            // the keyboard covers that bar, so scrolling the list is the ONLY
            // way back to the tabs mid-query — which is the accepted cost of
            // deleting the scope control (Dave's call: dismiss the keyboard to
            // change tab). Do not weaken it to `.interactively`: a partial drag
            // that snaps back leaves the bar covered.
            .scrollDismissesKeyboard(.immediately)
            // PRESENTED and PICKER surfaces keep the facet row on a top
            // `safeAreaInset` — below the kit bar when presented, below the
            // picker header. Opaque, rows scroll under it, no geometry
            // probes (the morph law). Their chrome is app-drawn, so the
            // system large-title machinery that broke this mount on tab
            // roots never runs on them; tabs pin the row as the list's own
            // section header instead (see the List above). ⚠️ Do NOT move
            // tabs back onto this inset — the failure is invisible to CI.
            .safeAreaInset(edge: .top, spacing: 0) {
                if !mode.isTab {
                    filterRow(shown: shown, hidden: hiddenByFilters)
                }
            }
            // SOFT at the bottom — the system's own gradient dissolve, which is
            // the third answer this edge has had and the one that holds both
            // constraints at once. `.hard` (139) draws a full-width blurred
            // SLAB for the bar to sit on, which Dave killed on 148; hiding it
            // outright (148) let row text read straight through the chrome —
            // his own build-148 screenshot has an equipment name legible
            // through the search field and the collapsed tab button. Soft only
            // shows where content is actually passing under, so there is no
            // slab to see on an empty stretch. ⚠️ On the SCROLLING CONTENT,
            // never a background on the bar — build 133's mistake.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
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
                            // ⚠️ `.center`, not `.top` (2026-08-01): the facet
                            // row is a PINNED header now, and the top of the
                            // scroll bounds is exactly where it floats — a row
                            // seated there lands behind the chips, taking its
                            // entrance flash with it. Same class as the rule
                            // that expands a missing-equipment group so an
                            // arrival never flashes on a hidden row.
                            proxy.scrollTo(AnyHashable(target), anchor: .center)
                        }
                        // Hold the identity until the flash has finished
                        // FADING, not merely started: `newlyAdded = nil`
                        // unmounts the row background the mark lives in, so a
                        // shorter hold cuts the fade off mid-way. Both arms
                        // read the duration off the flash itself.
                        try await Task.sleep(for: RowEntranceFlash.totalDuration)
                    } else {
                        try await Task.sleep(for: .milliseconds(80))
                        withAnimation(Theme.Anim.standard) {
                            proxy.scrollTo(AnyHashable(target), anchor: .center)
                        }
                        try await Task.sleep(for: RowEntranceFlash.totalDuration)
                    }
                } catch {
                    return
                }
                newlyAdded = nil
            }
        }
    }

    /// Only ever a genuinely empty match: with no query the whole scope shows,
    /// and un-doable items are grouped rather than hidden. Active facets get
    /// the promised escape (navigation.md: empty results never dead-end) —
    /// the create row is present regardless.
    private func emptyState(hiddenByFilters: Int) -> some View {
        VStack(spacing: 10) {
            // Name the FACET as the reason where it provably is one
            // (#507, Q13-A): "Nothing matches" over a live filter that
            // is doing the hiding tells you nothing you can act on.
            Text(emptyStateLine(hiddenByFilters: hiddenByFilters))
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
            if !filters.isEmpty(for: scope) {
                QuietKey(label: "Clear filters", identifier: "clearCatalogFilters") {
                    withAnimation(Theme.Anim.standard) {
                        filters.clear(scope: scope)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// "Nothing matches", plus the filters' share of the blame when they
    /// are provably holding something back for this exact query.
    private func emptyStateLine(hiddenByFilters: Int) -> String {
        hiddenByFilters > 0 ? "Nothing matches with these filters on." : "Nothing matches."
    }

    /// What the ACTIVE FACETS are keeping off the screen for the current
    /// query (#507, Q13-A), named and tappable.
    ///
    /// The exact-name guard already checks the UNFILTERED set, so an
    /// exact match can never be hidden behind a create row; a PARTIAL
    /// one could ("bench" under Kind=Cardio hides Bench Press and offers
    /// Create "Bench" — the easy path to a near-duplicate). This is that
    /// gap. The count rides `outcome`, so it costs nothing.
    ///
    /// ⚠️ QUERIED lists only. With no query there is no near-duplicate to
    /// guard against (the create row reads "New exercise" and opens the
    /// editor), and the summary chip's "N of M shown" is already saying
    /// the same thing one row above — a permanent second copy of it over
    /// every browse (swift-reviewer). The count still feeds that chip.
    private func hiddenByFiltersRow(_ count: Int) -> some View {
        QuietKey(
            label: "\(count) more \(scope.searchNoun(for: count)) hidden by filters · show",
            systemImage: "line.3.horizontal.decrease",
            identifier: "hiddenByFilters"
        ) {
            withAnimation(Theme.Anim.standard) {
                filters.clear(scope: scope)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: - The facet row (filtering returns, 2026-07-31)

    /// Per-scope single-select facet chips in a horizontal run, led by the
    /// summary chip whenever anything is active (the summarize-never-
    /// insta-clear law). State is `filters`; the engine applies it.
    ///
    /// Mounted two ways, both PINNED: the single section's header on tab
    /// roots (list-internal, so the system large-title bar never sees it —
    /// see `listBody`), and a top `safeAreaInset` on presented/picker
    /// surfaces, whose chrome is app-drawn.
    private func filterRow(shown: Int, hidden: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if !filters.isEmpty(for: scope) {
                    FilterSummaryChip(
                        facets: filters.activeFacets(for: scope),
                        shown: shown,
                        total: shown + hidden
                    ) {
                        withAnimation(Theme.Anim.standard) {
                            filters.clear(scope: scope)
                        }
                    }
                }
                switch scope {
                case .exercises:
                    // Kind leads: the coarsest axis, and the reason the
                    // cardio push wanted a facet at all — every cardio
                    // exercise files under Full Body, so no other facet
                    // reaches the cardio rows as a set (#475). The two
                    // BINARY facets keep their Menus; everything with a
                    // real list of options opens a tray (#498).
                    FacetTrayChip(name: "Kind", options: CatalogKind.allCases, display: \.label, selection: $filters.kinds, identifier: "facetKind")
                    FacetTrayChip(name: "Muscle", options: MuscleGroup.allCases, display: \.displayName, selection: $filters.muscles, identifier: "facetMuscle", searchPrompt: "Search muscle groups")
                    FacetTrayChip(name: "Movement", options: MovementPattern.allCases, display: \.displayName, selection: $filters.patterns, identifier: "facetMovement", searchPrompt: "Search movements")
                    FacetChip(name: "Mechanic", options: ExerciseMechanic.allCases, display: \.displayName, selection: $filters.mechanic, identifier: "facetMechanic")
                    FacetChip(name: "Sides", options: ExerciseLaterality.allCases, display: \.displayName, selection: $filters.laterality, identifier: "facetSides")
                case .kit:
                    FacetTrayChip(name: "Type", options: SeedData.EquipmentCategory.allCases, display: \.rawValue, selection: $filters.equipmentCategories, identifier: "facetType")
                case .routines:
                    FacetTrayChip(name: "Focus", options: RoutineTemplate.Focus.allCases, display: \.rawValue, selection: $filters.focuses, identifier: "facetFocus")
                    FacetTrayChip(name: "Effort", options: RoutineTemplate.Effort.allCases, display: \.rawValue, selection: $filters.efforts, identifier: "facetEffort")
                    FacetTrayChip(name: "Style", options: RoutineTemplate.Style.allCases, display: \.rawValue, selection: $filters.styles, identifier: "facetStyle")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .animation(Theme.Anim.standard, value: filters.isEmpty(for: scope))
        // OPAQUE — rows scroll under this band (the picker-field rule).
        .background(Theme.background)
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

    /// The MINE / CATALOG divider — a plain ROW since 2026-08-01, not a
    /// pinned section header: the list's one pinning header is the facet
    /// row (see `listBody`). It keeps its opaque fill anyway, so it reads
    /// as a divider rather than a floating label.
    @ViewBuilder
    private func tierLabelRow(_ section: FindOrCreateEngine.Section) -> some View {
        // An untitled section is the flat run (the presented equipment
        // catalog): no tiers, so nothing to divide.
        if !section.title.isEmpty {
            SheetSectionLabel("\(section.title) · \(section.count)")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .background(Theme.background)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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
        // The entrance flash rides the row BACKGROUND, not an overlay: the
        // background gets the row's true bounds, so the mark needs no
        // negative padding guessing at them (2026-07-28 — see
        // `RowEntranceFlash`). Both sides can be nil (a catalog template has
        // no stored model and nothing ever lands on it), so compare only real
        // ids — `nil == nil` would flash every template row at once.
        .listRowBackground(
            Group {
                if let id = result.modelID, newlyAdded == id {
                    RowEntranceFlash()
                } else {
                    Color.clear
                }
            }
        )
        .listRowSeparatorTint(Theme.border)
        // The arrival's authored beat: the row is held OUT of the list for
        // 300 ms, then fades in and pushes the rest down. Without this it
        // reads as a default List insert (the deleted RoutineCard carried it).
        .transition(.opacity)
    }

    private func exerciseRow(_ exercise: Exercise, result: FindOrCreateEngine.Result) -> some View {
        catalogRow { open(result) } content: {
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
        }
        // LEADING is curation. Favorite is creation-of-yours → green; toggles
        // off to a neutral UNFAV when already lit.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                exercise.isFavorite.toggle()
            } label: {
                Text(exercise.isFavorite ? "UNFAV" : "FAV")
            }
            .tint(exercise.isFavorite ? Theme.swipeNeutral : Theme.swipeAdd)
            .accessibilityIdentifier("favSwipe-\(exercise.name)")
        }
        // TRAILING is destructive, and only for customs — a built-in can't be
        // deleted, so it gets no trailing swipe at all.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !exercise.isBuiltIn {
                Button(role: .destructive) {
                    modelContext.delete(exercise)
                } label: {
                    Text("DELETE")
                }
                .tint(Theme.swipeDelete)
            }
        }
    }

    private func equipmentRow(
        _ equipment: Equipment,
        result: FindOrCreateEngine.Result,
        unlocked: Int
    ) -> some View {
        let inKit = kitNames.contains(equipment.name)
        return catalogRow { open(result) } content: {
            EquipmentRowContent(
                equipment: equipment,
                unlockedCount: unlocked,
                inKit: inKit ? true : nil,
                nameHighlight: highlight(equipment.name)
            )
        }
        // Membership is the kit's curation. The null kit is immutable, so it
        // gets no leading swipe at all.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isBodyweightKit {
                Button {
                    setMembership(equipment, !inKit)
                } label: {
                    Text(inKit ? "REMOVE" : "ADD")
                }
                // ⚠️ REMOVE is NEUTRAL, never the destructive red (Dave,
                // 2026-07-28). It drops the piece from the ACTIVE KIT — the
                // equipment still exists, still sits in your other kits, and
                // the same swipe puts it back. DELETE on the trailing edge
                // ends the object everywhere and only exists on customs.
                // Sharing one red made the single cue that separates them
                // say they were the same act. Neutral matches UNFAV on the
                // exercise row, which is the identical "turn my curation
                // off" gesture.
                .tint(inKit ? Theme.swipeNeutral : Theme.swipeAdd)
                .accessibilityIdentifier("quickAdd-\(equipment.name)")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !equipment.isBuiltIn {
                Button(role: .destructive) {
                    deleteEquipment(equipment)
                } label: {
                    Text("DELETE")
                }
                .tint(Theme.swipeDelete)
            }
        }
        .accessibilityIdentifier("equipmentCard-\(equipment.name)")
    }

    private func routineRow(_ routine: Routine, result: FindOrCreateEngine.Result) -> some View {
        catalogRow { open(result) } content: {
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
        }
        // Routines carry no leading curation — the MINE tier is the curation.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteRoutine(routine)
            } label: {
                Text("DELETE")
            }
            .tint(Theme.swipeDelete)
        }
    }

    /// One catalog row body: the whole row is the tap target, and NOTHING else
    /// in it is (the swipes live on the List row, not on the content).
    ///
    /// ⚠️ `.buttonStyle(.plain)`, never the default — inside a `List`, row taps
    /// route into default-styled buttons anywhere in the row, which was half of
    /// the build-12 disappearing-rows bug. `templateRow` has always used this
    /// shape; since 2026-07-27 every catalog row does.
    private func catalogRow<Content: View>(
        _ activate: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: activate) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // The hand-mirrored VoiceOver actions (#164) are GONE with the custom
    // rows: `.swipeActions` publishes its buttons as custom actions itself, so
    // re-declaring them would read every act twice in the rotor. The labels
    // move with the buttons — "FAV"/"DELETE" rather than the old sentence-case
    // "Favorite"/"Delete" — which is the one a11y-visible cost of the change.

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

    // Return does NOT open the top result (Dave, 2026-07-26) — it just puts the
    // keyboard away, which the native field does on its own. Submitting a
    // search is not choosing one, and a key that navigates on Return has to
    // out-guess you every time; it also took the stacked-duplicate-push hazard
    // with it (`path.append` is not idempotent, ui-interaction.md).

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

    // ONE verb grammar across the three catalogs (#507, b12): `New <object>`
    // with no query, `Create "<query>"` with one. The verb predicts the tap —
    // CREATE commits inline, ADD opens something ("Add to routine…", the
    // overview's "Add exercise"), and all three of these commit. Kit's
    // "Add … as equipment" was the one row that said Add and committed
    // anyway; the tab it sits on already names the type its empty-query form
    // spells out, and the new piece lands in MINE with the entrance flash,
    // which is where its kit membership reads.
    private var routinesCreateLabel: String {
        trimmedQuery.isEmpty ? "New routine" : "Create \(quotedQuery)"
    }

    private var exercisesCreateLabel: String {
        trimmedQuery.isEmpty ? "New exercise" : "Create \(quotedQuery)"
    }

    private var kitCreateLabel: String {
        trimmedQuery.isEmpty ? "New equipment" : "Create \(quotedQuery)"
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
            // …and now it SAYS so (#507, b9): the tray used to arrive
            // with no connection to the create row that summoned it.
            // ⚠️ It names the kit the way the SWITCHER does — the raw
            // reserved name, which is the only string the user has ever
            // seen for it — and borrows `kitHint`'s explanation verbatim
            // so the app has ONE account of what null is. A hand-written
            // description ("Bodyweight only…") named a kit that exists
            // under no such name (swift-reviewer).
            libraryTrayReason = "\(EquipmentLibrary.bodyweightName) is the no-equipment kit, so \(quotedQuery) can't go in it. Pick another kit."
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
    /// sequence: the routines scope, on a tab, with no query OR FACETS
    /// narrowing the rows, over the MINE tier's doable group. A facet-
    /// narrowed list has no order to write back — writing one demotes
    /// every filtered-out routine to the bottom (swift-reviewer, this PR).
    private func moveHandler(for section: FindOrCreateEngine.Section) -> ((IndexSet, Int) -> Void)? {
        let reorderable = scope == .routines
            && mode.isTab
            && trimmedQuery.isEmpty
            && filters.isEmpty(for: scope)
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
        guard ownsLandings else { return }
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
            clearFiltersHiding(filters.allows(routine))
            newlyAdded = routine.persistentModelID
        case .exercises:
            guard let pending = ExerciseArrival.pending else { return }
            ExerciseArrival.pending = nil
            path = NavigationPath()
            expandMissingGroups()
            clearFiltersHiding(allExercises.first { $0.persistentModelID == pending }.map { filters.allows($0) })
            newlyAdded = pending
        case .kit:
            guard let pending = EquipmentArrival.pending else { return }
            EquipmentArrival.pending = nil
            path = NavigationPath()
            clearFiltersHiding(allEquipment.first { $0.persistentModelID == pending }.map { filters.allowsEquipment(named: $0.name) })
            newlyAdded = pending
        }
    }

    /// A landed item that needs gear sits in a collapsed group; open the
    /// tier it actually landed in so its entrance flash isn't playing on
    /// a hidden row. ⚠️ Its OWN tier only (#507, b11): a landing is
    /// always something you just made, so it is always MINE, and opening
    /// CATALOG's group too dumped a wall of unrelated rows on screen at
    /// the exact moment the eye was going to the flash.
    private func expandMissingGroups() {
        expandedMissing.insert("MISSING_MINE")
    }

    /// The facet row is the OTHER thing that can hide a landed row
    /// (swift-reviewer, this PR): a just-created custom answers none of
    /// the attribute chips, so an active facet would swallow its landing
    /// — no row, no flash, reads as a failed save. Same rule as
    /// `expandMissingGroups`: a landing never targets a hidden row.
    /// `allowed` nil means the model couldn't be resolved against the
    /// live query — clear then too, visibility can't be proven.
    /// ⚠️ This is why the "not rated" group (#507) can never swallow a
    /// landing: a hand-built routine under an Effort facet fails
    /// `allows`, so the facets clear here and it lands in MINE. Do NOT
    /// "fix" that by expanding UNRATED instead — the group is collapsed
    /// by default, so the flash would still play on a hidden row.
    private func clearFiltersHiding(_ allowed: Bool?) {
        guard !filters.isEmpty(for: scope), allowed != true else { return }
        filters.clear(scope: scope)
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



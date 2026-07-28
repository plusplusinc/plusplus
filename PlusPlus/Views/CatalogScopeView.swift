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

    /// The query. In `.tab` mode it lives in the ROOT — the segmented scope
    /// picker sits outside this view and switching scope must not lose what you
    /// typed; in `.presented` mode the surface owns it.
    @Binding private var boundQuery: String
    // Per-scope match COUNTS are gone with the hand-drawn bar (2026-07-25):
    // there are no scope labels in the chrome to paint them on. The segmented
    // picker in the tab bar's accessory is the cross-scope affordance now.
    /// Which tab root this is: the reveal drawer's per-tab swipe gate keys on
    /// it, and so does `ownsLandings`.
    ///
    /// That second job is load-bearing since the catalogs became tabs again
    /// (2026-07-26): a `Tab`'s content is its own view tree, so the Routines tab
    /// and a search tab dialled to routines are two live instances of this view.
    /// Anything answering a broadcast has to name one of them.
    private let tabKey: String
    /// The SEARCH tab's scope selection, and nothing else's.
    ///
    /// ⚠️ The field and the scope bar live INSIDE this view's `NavigationStack`,
    /// not on the `Tab` in `RootTabView` (build 140 put them there and the scope
    /// bar never rendered). `.searchScopes` needs `.searchable` on a view inside
    /// a NAVIGATION CONTAINER; attached to `CatalogScopeView` from outside, the
    /// modifier sits ABOVE this stack, so the field still morphed — the tab role
    /// gives it that — but the scope bar had no search presentation to attach
    /// to. Non-nil marks the one instance that owns both.
    private let searchScope: Binding<FindScope>?
    /// Picker mode only: a row tap (or a fresh create) hands the item back
    /// here instead of opening it.
    private let onPick: ((Exercise) -> Void)?
    /// Picker mode's sheet title ("Add exercise" / "Swap for…").
    private var pickerTitle = ""

    /// A tab root. `searchScope` is non-nil ONLY on the search tab — that is
    /// what makes this instance the one carrying the field and the scope bar.
    init(
        scope: FindScope,
        query: Binding<String>,
        tab: AppTab,
        searchScope: Binding<FindScope>? = nil
    ) {
        self.scope = scope
        self.mode = .tab
        self._boundQuery = query
        self.tabKey = tab.rawValue
        self.searchScope = searchScope
        self.onPick = nil
    }

    /// A presented catalog (the pushed equipment catalog's replacement).
    init(scope: FindScope, setupMode: Bool = false) {
        self.scope = scope
        self.mode = .presented(setupMode: setupMode)
        self._boundQuery = .constant("")
        self.tabKey = ""
        self.searchScope = nil
        self.onPick = nil
    }

    /// A picker sheet: the same catalog, but choosing rather than browsing.
    init(picking scope: FindScope, title: String, onPick: @escaping (Exercise) -> Void) {
        self.scope = scope
        self.mode = .picker
        self._boundQuery = .constant("")
        self.tabKey = ""
        self.searchScope = nil
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
    // No `openSwipeRow` here any more: the catalog rows use NATIVE
    // `.swipeActions` (2026-07-27), so UIKit owns which row is open, how it
    // closes, and — the point of the change — the arbitration with the scroll
    // pan. `SwipeRevealRow` survives only where a row is not in a `List`.
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

    /// The one tab that hosts the system search field.
    private var isSearchSurface: Bool { searchScope != nil }

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

    /// The app's content column, and every gap in the search surface's bar row:
    /// the ++ key sits this far from the screen edge, so the control's two gaps
    /// match it and the row reads as evenly spaced (Dave, build 150).
    private let barGap: CGFloat = 16

    /// A tab root: its own stack, the SYSTEM navigation bar, and the bottom
    /// bar's field. Every value destination registers HERE, at the stack root
    /// (#262), so back returns to the results with query and scroll intact.
    ///
    /// **The hand-drawn `CatalogTabHeader` is gone** (Dave, 2026-07-26: "fuck
    /// it, let's kill our custom header"). The app hid the navigation bar on
    /// every tab root and drew its own title row, which is the one thing search
    /// cannot live with: `.searchable` and its scope bar belong to the
    /// navigation bar's presentation, so hiding it left the field with nowhere
    /// to fall back to (build 135's invisible input) and the scope bar with
    /// nothing to attach to (build 140's missing scopes). The title, the ++ key
    /// and the kit switcher move into the real bar; nothing is lost but the
    /// hand-drawing.
    @ViewBuilder
    private var tabBody: some View {
        // The SEARCH surface — and ONLY it — measures its own width, because
        // only it lays out the bar row by hand.
        //
        // ⚠️ A PURE layout read: the proxy's size is used directly and never
        // written to state. That distinction is the law — an
        // `.onGeometryChange` or a `PreferenceKey` probe inside the TabView
        // subtree is the documented iOS 26 trigger for the search-role morph
        // failing on first activation, because it feeds layout back into state.
        // A `GeometryReader` that merely reads is not that.
        //
        // ⚠️ It is still not free, which is why the other four roots don't pay
        // for it: the closure re-runs on every size change, height included, and
        // rebuilding this view re-runs the ranking pipeline (`displayedSections`
        // is hoisted in `listBody` precisely because it is expensive). On the
        // search tab that pipeline already runs per keystroke, so the extra
        // passes are marginal; on a scrolling catalog the tab bar minimising
        // would have re-ranked the whole list mid-scroll for nothing.
        if isSearchSurface {
            GeometryReader { proxy in
                tabStack(barWidth: proxy.size.width)
            }
        } else {
            tabStack(barWidth: nil)
        }
    }

    private func tabStack(barWidth: CGFloat?) -> some View {
        NavigationStack(path: $path) {
            listBody
                .background(Theme.background)
                // The SEARCH surface carries no title (Dave, 2026-07-26): the
                // scope control already names the catalog, so a title is
                // duplicative — and a large one FLASHES on entry, collapsing
                // away as search presents and leaving the top area empty. The
                // bar itself stays: hiding it is what left `.searchable` with
                // nowhere to fall back to in the first place.
                .navigationTitle(isSearchSurface ? "" : scope.label)
                .navigationBarTitleDisplayMode(isSearchSurface ? .inline : .large)
                .toolbar {
                    if let searchScope {
                        // ⚠️ On the SEARCH surface the app owns the WHOLE bar
                        // row as one `.principal` item, rather than letting the
                        // system place three (Dave, build 150: make the control
                        // take the available width, less an even gap).
                        //
                        // Why it has to be one item: a principal item is a
                        // TITLE VIEW, and UIKit centres a title view **in the
                        // bar**, not in the space left between the side items.
                        // So the two gaps differ by exactly the difference in
                        // the side items' widths — measured on build 150, a
                        // 42 pt ++ key against a 78 pt kit switcher gave 76 pt
                        // of gap on the left and 40 pt on the right. No amount
                        // of padding fixes that class, and it moves with the
                        // kit's name. `.frame(maxWidth: .infinity)` did nothing
                        // either: the bar proposes an unbounded width, so the
                        // control just takes its ideal size.
                        //
                        // With no leading or trailing items the title view gets
                        // the whole bar, so an explicit width of the screen
                        // less two `barGap`s lands the row on the app's own
                        // content column, and every gap in it is ours to set.
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: barGap) {
                                AppMenuKey()
                                ScopeSegmentedControl(scope: searchScope)
                                    // Absorbs whatever the two keys leave. No
                                    // minimum: an `HStack` never offers one
                                    // flexible child more than its share, so
                                    // the switcher can't take more than half of
                                    // what's left — it shrinks and truncates
                                    // its own text first, which is the right
                                    // thing to yield here. A hard floor would
                                    // instead make the ROW overflow on a narrow
                                    // screen and shear the keys off both ends.
                                    .frame(maxWidth: .infinity)
                                    // The raised keys are 4 pt taller than they
                                    // look: `RaisedKeyStyle` pads the bottom by
                                    // its travel to leave room for the plate,
                                    // so their visible caps centre 2 pt above
                                    // this row's centre. Match the padding and
                                    // the three line up.
                                    .padding(.bottom, 4)
                                LibrarySwitcherKey(name: activeKitName, identifier: scope.switcherIdentifier) {
                                    showingLibraryTray = true
                                }
                            }
                            // ⚠️ Optional, not `max(0, …)`: a tab's content is
                            // built lazily and the first layout pass can report
                            // a zero size — on the search tab that first pass IS
                            // the first activation. `nil` leaves the row at its
                            // ideal size for that frame instead of collapsing
                            // it to nothing.
                            .frame(width: barWidth.flatMap { $0 > barGap * 2 ? $0 - barGap * 2 : nil })
                        }
                        // The row brings its own key chrome and the control
                        // brings its own track, so it opts out of the toolbar's
                        // shared glass — without this they nest inside a system
                        // capsule, the box-in-a-box that killed the accessory.
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        // Every other root: the system places the two keys, and
                        // the title sits between them.
                        ToolbarItem(placement: .topBarLeading) { AppMenuKey() }
                            .sharedBackgroundVisibility(.hidden)
                        // The kit is CONTEXT on every catalog, never a filter
                        // chip: it decides which rows fall into the "require
                        // more equipment" group below.
                        ToolbarItem(placement: .topBarTrailing) {
                            LibrarySwitcherKey(name: activeKitName, identifier: scope.switcherIdentifier) {
                                showingLibraryTray = true
                            }
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
            // The system field, on the SEARCH tab only, and INSIDE the stack —
            // see `searchScope`.
                .modifier(SearchPresentation(query: $boundQuery, scope: searchScope))
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
        // Changing scope is the search tab dialling the accessory — the same
        // surface looking at something else, so it stays MOUNTED (an `.id(scope)`
        // would rebuild it, which is exactly what stops a scope change feeling
        // like one). Only what can't survive the change resets: a pushed detail
        // belonging to the old catalog, and which groups were opened in it.
        .onChange(of: scope) { _, _ in
            // ⚠️ Guarded, and it matters more than it looks. This fires on
            // EVERY scope tap, and on the search tab those taps happen while a
            // search presentation is live — inside the very NavigationStack
            // `path` belongs to. Assigning an already-empty path still
            // publishes a change and re-evaluates the stack, which is churn
            // underneath the thing that must not be re-created beneath itself.
            if !path.isEmpty { path = NavigationPath() }
            if !expandedMissing.isEmpty { expandedMissing = [] }
        }
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
    /// The catalog tab that owns the scope is the answer, never "whichever
    /// instance is showing it" — the search tab dialled to routines shows
    /// routines too, and a landing switches away from search by definition, so
    /// letting search consume would play the entrance flash on the surface
    /// you're being taken off. Both slots survive an unbuilt tab, so the
    /// owner can consume late, on appear.
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
            .tint(exercise.isFavorite ? Theme.textFaint : Theme.accent)
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
                .tint(Theme.destructive)
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
                .tint(inKit ? Theme.textFaint : Theme.accent)
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
                .tint(Theme.destructive)
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
            .tint(Theme.destructive)
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


/// The system search field and the scope control, attached INSIDE a catalog
/// tab's `NavigationStack` and only on the search tab.
///
/// A modifier so the branch lives in one place rather than forking the stack's
/// body. The condition is safe to branch on because it is fixed per instance:
/// `searchScope` is a `let` decided at init, so a given `CatalogScopeView`
/// either always carries search or never does. Search presentation must not be
/// re-created underneath itself, and this can't do that.
private struct SearchPresentation: ViewModifier {
    @Binding var query: String
    /// Non-nil only on the search tab. Everywhere else this modifier is inert.
    let scope: Binding<FindScope>?

    func body(content: Content) -> some View {
        if let scope {
            content
                // The scope control is NOT here — it's a `.principal`
                // `ToolbarItem` on the navigation bar, between the ++ key and
                // the kit switcher (see `tabBody`'s toolbar, and
                // `ScopeSegmentedControl` for the five placements that came
                // before it). ⚠️ NO `.searchScopes` either: on a bottom-aligned
                // field morphed out of `Tab(role: .search)` the system's own
                // scope bar renders exactly once per app run, at the top,
                // nowhere near the field it scopes.
                .searchable(text: $query, prompt: "Search \(scope.wrappedValue.searchNoun)")
                // Keep the bar's OTHER content — the ++ key, the kit switcher,
                // and now the scope control itself — while search is active
                // (Dave, build 147). Activating search otherwise tells the
                // navigation bar to clear its content and give search the room:
                // the system's `.automatic` behaviour, and the same mechanism
                // that emptied the top band on 143 before the title came off.
                // Those keys are how you reach the drawer and change kit;
                // losing them the moment you tap the field is a dead end, not a
                // decluttering. ⚠️ Now LOAD-BEARING for the scope control too.
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
    }
}

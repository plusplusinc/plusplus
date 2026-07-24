import SwiftUI
import SwiftData
import PlusPlusKit

/// The pre-scoped deep link into Find or create: a tab's Add row opens
/// the surface already on its scope (Routines / Kit). The scope is a
/// HANDOFF SLOT, same shape as `RoutineArrival` — the surface may not be
/// mounted when the row fires, so it consumes the slot on appear.
@MainActor
enum FindOrCreateLaunch {
    static var pending: FindScope?

    static func open(_ scope: FindScope) {
        pending = scope
        NotificationCenter.default.post(name: .plusplusFindOrCreate, object: nil)
    }
}

/// Universal search — "Find or create" (design handoff 2026-07-23). ONE
/// place to find or make a routine, an exercise, or a piece of equipment,
/// yours or the catalog's, living behind the tab bar's search item. The
/// per-tab header magnifiers retired into this surface; in-picker and
/// pushed-catalog search stay.
///
/// Layout: tab-root header grammar (++ key · title · kit switcher — kit
/// is CONTEXT, never a filter chip) → the scope segmented control (a MODE,
/// so it leads) → the Doable filter chip → create row → results, with the
/// search field + a text Done key (never ✕) anchored in a BOTTOM bar that
/// takes over the tab bar (the four tabs + search circle are hidden while
/// this surface is up; the field rides above the keyboard and settles onto
/// the tab-bar line when it drops).
/// The create row is present unless the query EXACTLY names an item that
/// already exists (a create there would only duplicate the row right
/// below it — `FindOrCreateEngine.Collisions`); it never dead-ends, since
/// an exact-name match always ranks into the results. An empty query
/// shows everything, mine-first — narrowed by the Doable filter (default
/// on, routines/exercises the active kit can do; an exact name always
/// surfaces). Rows are clean (decision A): tap pushes detail onto THIS
/// stack — back returns with query, scope, and scroll intact — and the
/// long-press context menu carries the quick acts. The QUERY is ephemeral
/// per-entry; the Doable FILTER persists (a preference, not search state);
/// the active kit is the one app-wide pointer, switched only through the tray.
struct FindOrCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    /// Done returns to wherever the user came from (the root tracks the
    /// previously selected tab).
    let onDone: () -> Void

    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var scope: FindScope = .all
    /// One-shot focus intent (#233) — armed on every surface entry so the
    /// keyboard rises, and re-armed by the empty-query Kit create row
    /// ("type a name first" = put the cursor back).
    @State private var wantsFocus = false
    @State private var showingLibraryTray = false
    @State private var creatingExercise = false
    @State private var namingRoutine = false
    @State private var newRoutineName = ""
    /// The "Doable" filter: show only routines/exercises the active kit can
    /// do (default on). A FILTER preference, so unlike the query it PERSISTS
    /// across entries (the catalogs persist their availability facet too) —
    /// someone who wants the full catalog turns it off once. The chip is the
    /// two-way control, always at the top so the trip back is as reachable as
    /// the trip out.
    @AppStorage("findOrCreateDoableOnly") private var doableOnly = true

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    private var kitNames: Set<String> {
        activeLibrary?.memberNames ?? []
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sections: [FindOrCreateEngine.Section] {
        FindOrCreateEngine.sections(
            query: trimmedQuery,
            scope: scope,
            exercises: allExercises,
            equipment: allEquipment,
            routines: routines,
            templates: RoutineCatalog.all,
            kitNames: kitNames,
            // Kit scope lists equipment, which the Doable filter never
            // touches — so it only narrows in All/Routines/Exercises.
            doableOnly: doableOnly && scope != .kit
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(title: "Find or create") {
                    // The SAME app-wide, persisting switch as the other tab
                    // headers — kit is context here, never a filter chip
                    // (the kit-vs-filter tension, settled in the handoff).
                    LibrarySwitcherKey(
                        name: activeLibrary?.name ?? EquipmentLibrary.defaultName,
                        identifier: "searchKitSwitcher"
                    ) {
                        showingLibraryTray = true
                    }
                }
                // Scope + the Doable filter are the TOP controls (mode +
                // narrowing). The search field lives in the BOTTOM bar, where
                // it takes over the tab bar (thumb-reachable, results directly
                // above it).
                scopeSegmented
                doableFilterRow
                resultsList
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // In Find or create the search field TAKES OVER the tab bar: hide
            // the tab bar and anchor the field + Done key at the bottom in its
            // place (Dave). Keyboard-aware via safeAreaInset — the bar rides
            // above the keyboard and settles onto the tab-bar line when it
            // drops. A CUSTOM field, not `.searchable`, so the iOS 26
            // search-morph geometry bug (a sibling tab's `.onGeometryChange`)
            // never applies. ⚠️ Device-pass: iOS 26 renders `role: .search` as
            // a SEPARATED accessory circle beside the tab group — confirm
            // `.tabBar` hiding takes that circle down with the four tabs (not
            // leaving it floating over the new bottom bar).
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            // The four result types push onto THIS stack (registered at the
            // root, #262) so back/swipe-back returns to results with query,
            // scope, and scroll intact — search is a stack, not a modal.
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
            .navigationDestination(for: Equipment.self) { equipment in
                EquipmentDetailScreen(equipment: equipment)
            }
            .navigationDestination(for: RoutineRef.self) { ref in
                if let routine = modelContext.routine(uuid: ref.uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $path) { routine in
                    // Adding a catalog routine LANDS on Routines with the
                    // entrance flash, from here like everywhere else.
                    routine.uuid.map { RoutineArrival.land($0) }
                }
            }
            .sheet(isPresented: $showingLibraryTray) {
                EquipmentLibraryTray()
            }
            .sheet(isPresented: $creatingExercise) {
                ExerciseEditorView(prefillName: trimmedQuery) { exercise in
                    // The editor only INSERTS — save here so the id the
                    // landing keys on is permanent, not the temporary one
                    // an autosave would swap out from under the flash
                    // (swiftdata.md; swift-reviewer catch).
                    try? modelContext.save()
                    ExerciseArrival.land(exercise.persistentModelID)
                }
            }
            .alert("New routine", isPresented: $namingRoutine) {
                TextField("Name", text: $newRoutineName)
                Button("Create") { createRoutine(named: newRoutineName) }
                Button("Cancel", role: .cancel) { newRoutineName = "" }
            }
        }
        .revealRoot(tab: "search", atRoot: path.isEmpty)
        // Favorites / kit / routine changes made from here reach GitHub
        // when you leave, like every tab.
        .syncsProgramOnClose()
        // Ephemeral per-entry state (stale invisible queries read as data
        // loss): every ENTRY into the tab resets to a blank query on All —
        // or onto a pre-scoped launch — with the keyboard rising. Attached
        // to the stack, not the root content, so a pop-back inside the
        // stack does NOT reset (back returns to live results).
        .onAppear(perform: enterSurface)
    }

    private func enterSurface() {
        let launch = FindOrCreateLaunch.pending
        FindOrCreateLaunch.pending = nil
        scope = launch ?? .all
        query = ""
        path = NavigationPath()
        wantsFocus = true
    }

    // MARK: - Field + scopes

    /// The bottom bar that takes over the tab bar while Find or create is up:
    /// the search field + a Done key. A text Done (not a ✕ — the app reserves
    /// ✕ for collapse-search) returns to the tab you came from. A top hairline
    /// over the surface fill separates it from the results scrolling above.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            SearchFieldBody(
                config: HeaderSearchConfig(
                    text: $query,
                    prompt: "Routines, exercises, equipment…",
                    identifier: "findOrCreateField"
                ),
                wantsFocus: $wantsFocus,
                onSubmit: openTopResult
            )
            SheetDismissKey(identifier: "findOrCreateDone", action: onDone)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // Opaque (not a translucent material) so results can't bleed through,
        // and extended under the bottom safe area so the home-indicator strip
        // fills solid with no seam under the bar.
        .background {
            Theme.background.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 0.5)
        }
    }

    /// Scope as a content-width segmented control (icons on the three typed
    /// scopes, "All" text-only — no natural glyph, and content widths let it
    /// sit next to its neighbors without a gap). One selection, one sliding
    /// pill; the labels/symbols/ids track `FindScope.allCases` in order.
    private var scopeSegmented: some View {
        SegmentedTabs(
            options: ["All", "Routines", "Exercises", "Kit"],
            selectedIndex: Binding(
                get: { FindScope.allCases.firstIndex(of: scope) ?? 0 },
                set: { scope = FindScope.allCases[$0] }
            ),
            symbols: [nil, "checklist", "figure.strengthtraining.traditional", "dumbbell"],
            identifiers: FindScope.allCases.map { "findScope-\($0.rawValue)" },
            widthsByContent: true
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The Doable filter: hide what the active kit can't do. Off reveals
    /// everything with the rows' own amber "needs X" tags. Absent in Kit
    /// scope, where results are equipment (nothing to "do"). This chip is
    /// the persistent two-way control — the trip back to filtered is the
    /// same tap, always in reach here rather than stranded below results.
    @ViewBuilder
    private var doableFilterRow: some View {
        if scope != .kit {
            HStack(spacing: 0) {
                SelectableChip(
                    label: "Doable",
                    isSelected: doableOnly,
                    identifier: "findDoableFilter",
                    systemImage: nil
                ) {
                    doableOnly.toggle()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        // One pass per render, shared by every equipment row ("N exercises").
        let unlockedCounts = exerciseCountsByEquipment
        let collisions = self.collisions
        return List {
            if showsCreateRow(collisions) {
                createRow(collisions)
            }
            // Real Sections (not loose header rows) so `.listStyle(.plain)`
            // PINS each heading to the top of the scroll area until the next
            // section's heading pushes it up — one sticky heading at a time.
            ForEach(sections) { section in
                Section {
                    ForEach(section.results) { result in
                        resultRow(result, unlockedCounts: unlockedCounts)
                    }
                    if section.moreCount > 0 {
                        moreRow(section)
                    }
                } header: {
                    sectionHeaderView(section)
                }
            }
            if sections.isEmpty {
                emptyState
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// Empty results are never a bare dead end. If the Doable filter is what
    /// emptied them (matches exist, just not with this kit), say so and offer
    /// the one-tap way through — the "Clear filters"-key grammar, so a locked
    /// search never reads as "nothing exists."
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            if doableHidingMatches {
                Text("Nothing here your kit can do.")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textFaint)
                QuietKey(label: "Show all", systemImage: "line.3.horizontal.decrease", identifier: "findShowAll") {
                    doableOnly = false
                }
            } else {
                Text("Nothing matches.")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// True when the Doable filter alone is emptying the results — the same
    /// query would show rows with the filter off. Only computed when the
    /// filtered results are already empty, so the extra pass is rare.
    private var doableHidingMatches: Bool {
        guard doableOnly, scope != .kit else { return false }
        return !FindOrCreateEngine.sections(
            query: trimmedQuery,
            scope: scope,
            exercises: allExercises,
            equipment: allEquipment,
            routines: routines,
            templates: RoutineCatalog.all,
            kitNames: kitNames,
            doableOnly: false
        ).isEmpty
    }

    private func sectionHeaderView(_ section: FindOrCreateEngine.Section) -> some View {
        Group {
            if let target = section.scopeTarget {
                // An All-scope section header is a door into its scope —
                // same jump as the more-row beneath it.
                Button {
                    scope = target
                } label: {
                    SheetSectionLabel("\(section.title) · \(section.count)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                SheetSectionLabel("\(section.title) · \(section.count)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        // Full-bleed SOLID background: a pinned header floats over the rows
        // scrolling beneath it, so a clear fill would let their text show
        // through. Matches the surface background, so it reads seamless.
        .background(Theme.background)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .textCase(nil)
    }

    private func moreRow(_ section: FindOrCreateEngine.Section) -> some View {
        Button {
            if let target = section.scopeTarget { scope = target }
        } label: {
            // Chevron, not ＋: this is navigation into the scope
            // (＋ stays reserved for creation).
            HStack(spacing: 5) {
                Text("\(section.moreCount) more")
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("findMore-\(section.id)")
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
    }

    @ViewBuilder
    private func resultRow(_ result: FindOrCreateEngine.Result, unlockedCounts: [PersistentIdentifier: Int]) -> some View {
        let row = Button {
            open(result)
        } label: {
            rowContent(result, unlockedCounts: unlockedCounts)
        }
        .buttonStyle(.plain)
        // Long-press peek (decision A: rows stay clean; the quick acts
        // live one press away). A UIKit interaction, not a SwiftUI
        // gesture, so it can't starve the scroll (#99's trap).
        .contextMenu { quickActs(result) }

        row
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
    }

    @ViewBuilder
    private func rowContent(_ result: FindOrCreateEngine.Result, unlockedCounts: [PersistentIdentifier: Int]) -> some View {
        switch result.item {
        case .exercise(let exercise):
            // Modality figures show in All AND Exercises scope — they carry
            // information beyond type (the one type-icon exception).
            ExerciseRowContent(
                exercise: exercise,
                available: kitNames,
                leadingSymbol: exercise.modalitySymbolName,
                nameHighlight: highlight(exercise.name)
            )
        case .equipment(let equipment):
            EquipmentRowContent(
                equipment: equipment,
                unlockedCount: unlockedCounts[equipment.persistentModelID] ?? 0,
                inKit: kitNames.contains(equipment.name) ? true : nil,
                leadingSymbol: scope == .all ? "dumbbell" : nil,
                nameHighlight: highlight(equipment.name)
            )
        case .routine(let routine):
            SearchRoutineRow(
                title: routine.name,
                highlight: highlight(routine.name),
                capsules: routineCapsules(
                    matched: result.matchedExerciseName,
                    gear: routine.gearAvailability(activeNames: kitNames)
                ),
                leadingSymbol: scope == .all ? "checklist" : nil
            )
        case .template(let template):
            SearchRoutineRow(
                title: template.name,
                highlight: highlight(template.name),
                capsules: routineCapsules(
                    matched: result.matchedExerciseName,
                    gear: template.equipmentNames.map { (name: $0, available: kitNames.contains($0)) }
                ),
                leadingSymbol: scope == .all ? "checklist" : nil
            )
        }
    }

    /// A routine row stays calm: the "has X" explainer (when the match came
    /// through a contained exercise) plus ONLY the amber missing pieces —
    /// available gear says nothing a routine row needs to say here.
    private func routineCapsules(matched: String?, gear: [(name: String, available: Bool)]) -> [CardCapsule] {
        var capsules: [CardCapsule] = []
        if let matched {
            capsules.append(CardCapsule(text: "has \(matched)"))
        }
        capsules += RoutineCardCapsules.gearCapsules(gear.filter { !$0.available })
        return capsules
    }

    private func highlight(_ name: String) -> [Range<String.Index>] {
        guard !trimmedQuery.isEmpty else { return [] }
        return FuzzySearch.highlightRanges(query: trimmedQuery, in: name)
    }

    /// One relationship pass per render (the equipment catalog's
    /// `exerciseIndex` pattern) so every equipment row's "N exercises"
    /// capsule doesn't rescan the catalog.
    private var exerciseCountsByEquipment: [PersistentIdentifier: Int] {
        var counts: [PersistentIdentifier: Int] = [:]
        for exercise in allExercises {
            for gear in exercise.equipment where !gear.isDeleted {
                counts[gear.persistentModelID, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Opening results

    private func open(_ result: FindOrCreateEngine.Result) {
        switch result.item {
        case .exercise(let exercise):
            path.append(exercise)
        case .equipment(let equipment):
            path.append(equipment)
        case .routine(let routine):
            // The routine family pushes by uuid, never the model
            // (the tray-flicker law).
            routine.uuid.map { path.append(RoutineRef(uuid: $0)) }
        case .template(let template):
            path.append(template)
        }
    }

    /// Return opens the best hit — the first row of the first section.
    private func openTopResult() {
        guard let top = sections.first?.results.first else { return }
        open(top)
    }

    @ViewBuilder
    private func quickActs(_ result: FindOrCreateEngine.Result) -> some View {
        switch result.item {
        case .exercise(let exercise):
            Button {
                exercise.isFavorite.toggle()
            } label: {
                Label(exercise.isFavorite ? "Unfavorite" : "Favorite",
                      systemImage: exercise.isFavorite ? "star.slash" : "star")
            }
        case .equipment(let equipment):
            // The null kit is immutable; its switcher is the way out.
            if activeLibrary?.isBodyweight != true {
                let inKit = kitNames.contains(equipment.name)
                Button {
                    // The state flip IS the feedback: the row crosses
                    // MINE/CATALOG, no landing.
                    activeLibrary?.setMembership(equipment, !inKit)
                    try? modelContext.save()
                } label: {
                    Label(inKit ? "Remove from kit" : "Add to kit",
                          systemImage: inKit ? "minus.circle" : "plus.circle")
                }
            }
        case .routine(let routine):
            Button {
                // The Siri/calendar start pathway: the root switches to
                // Today, which starts the session (and speaks up if the
                // routine can't start).
                NotificationCenter.default.post(name: .plusplusStartRoutine, object: routine.name)
            } label: {
                Label("Start", systemImage: "play.fill")
            }
        case .template(let template):
            Button {
                addTemplate(template)
            } label: {
                Label("Add to routines", systemImage: "plus")
            }
        }
        Button {
            open(result)
        } label: {
            Label("Open", systemImage: "chevron.right")
        }
    }

    // MARK: - Create row

    /// Exact-name collisions for the live query — a create is dropped when
    /// its type would duplicate an item that already exists under that name.
    private var collisions: FindOrCreateEngine.Collisions {
        FindOrCreateEngine.collisions(
            query: trimmedQuery,
            exercises: allExercises,
            equipment: allEquipment,
            routines: routines,
            templates: RoutineCatalog.all
        )
    }

    /// All-scope offers three creates; equipment needs a name, and any type
    /// whose name is already taken drops out. The row hides only when NONE
    /// remain (an exact match of all three at once — vanishingly rare, but
    /// then the results carry every one of them).
    private func allOffersEquipmentCreate(_ collisions: FindOrCreateEngine.Collisions) -> Bool {
        !trimmedQuery.isEmpty && !collisions.equipment
    }

    private func showsCreateRow(_ collisions: FindOrCreateEngine.Collisions) -> Bool {
        switch scope {
        case .all:
            return !collisions.exercise || !collisions.routine || allOffersEquipmentCreate(collisions)
        case .routines:
            return !collisions.routine
        case .exercises:
            return !collisions.exercise
        case .kit:
            return !collisions.equipment
        }
    }

    @ViewBuilder
    private func createRow(_ collisions: FindOrCreateEngine.Collisions) -> some View {
        Group {
            switch scope {
            case .all:
                CreateMenuRow(label: allCreateLabel, identifier: "findCreateMenu") {
                    createChooserItems(collisions)
                }
            case .routines:
                CreateRow(label: routinesCreateLabel, identifier: "createBlankRoutine") {
                    createRoutineFromQuery()
                }
            case .exercises:
                CreateRow(label: exercisesCreateLabel, identifier: "findCreateExercise") {
                    creatingExercise = true
                }
            case .kit:
                CreateRow(label: kitCreateLabel, identifier: "findCreateEquipment") {
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

    private var allCreateLabel: String {
        trimmedQuery.isEmpty ? "Create…" : "Create \(quotedQuery)…"
    }

    private var routinesCreateLabel: String {
        trimmedQuery.isEmpty ? "New routine" : "New routine \(quotedQuery)"
    }

    private var exercisesCreateLabel: String {
        trimmedQuery.isEmpty ? "New exercise" : "Create \(quotedQuery)"
    }

    private var kitCreateLabel: String {
        trimmedQuery.isEmpty ? "New equipment…" : "Add \(quotedQuery) as equipment"
    }

    /// The All-scope chooser: the query hasn't said what it wants to
    /// become. Equipment needs a name, so its entry only appears with one.
    /// Any type whose exact name is already taken drops out — the chooser
    /// never offers to duplicate an item the results already list.
    @ViewBuilder
    private func createChooserItems(_ collisions: FindOrCreateEngine.Collisions) -> some View {
        if !collisions.exercise {
            Button {
                creatingExercise = true
            } label: {
                Label(trimmedQuery.isEmpty ? "New exercise" : "Create exercise \(quotedQuery)",
                      systemImage: "figure.strengthtraining.traditional")
            }
        }
        if !collisions.routine {
            Button {
                createRoutineFromQuery()
            } label: {
                Label(trimmedQuery.isEmpty ? "New routine" : "New routine \(quotedQuery)",
                      systemImage: "checklist")
            }
        }
        if allOffersEquipmentCreate(collisions) {
            Button {
                createEquipmentFromQuery()
            } label: {
                Label("Add \(quotedQuery) as equipment", systemImage: "dumbbell")
            }
        }
    }

    // MARK: - Create actions

    /// A queried create is direct — the query IS the name (the "Add
    /// <query>" convention); an empty one asks for a name first (the
    /// routine catalog's alert), never minting junk "New Routine" rows.
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
        // Synchronous save: permanent ids before any presentation keys on
        // them, and the landing resolves by uuid (swiftdata.md).
        try? modelContext.save()
        routine.uuid.map { RoutineArrival.land($0) }
    }

    /// The equipment-catalog create recipe: dedupe on the lowercased name
    /// (typing "barbell" over an existing Barbell just adds it to the
    /// kit), insert if new, join the active kit, save synchronously, land.
    private func createEquipmentFromQuery() {
        // The null kit is immutable (setMembership no-ops; the Kit tab
        // hides its Add row for the same reason) — an unguarded create
        // would land on the null kit's empty list and read as data loss
        // (swift-reviewer catch). Adding means switching first: open the
        // tray, which explains the null kit and offers the switch.
        guard activeLibrary?.isBodyweight != true else {
            showingLibraryTray = true
            return
        }
        let name = trimmedQuery.sentenceCasedFirst
        guard !name.isEmpty else {
            // "Type a name first": put the cursor back in the field.
            wantsFocus = true
            return
        }
        let item: Equipment
        if let existing = allEquipment.first(where: { $0.name.lowercased() == name.lowercased() }) {
            item = existing
        } else {
            let created = Equipment(name: name, isBuiltIn: false)
            modelContext.insert(created)
            item = created
        }
        activeLibrary?.setMembership(item, true)
        try? modelContext.save()
        EquipmentArrival.land(item.persistentModelID)
    }

    private func addTemplate(_ template: RoutineTemplate) {
        // One-shot against a fast double-fire (the #189 duplicate-name
        // class; RoutineTemplateDetailScreen's `added` guard, applied
        // here as the same name-shadow rule the results already use).
        guard !routines.contains(where: { $0.name.lowercased() == template.name.lowercased() }) else { return }
        let routine = template.instantiate(in: modelContext, among: routines)
        try? modelContext.save()
        routine.uuid.map { RoutineArrival.land($0) }
    }
}

/// The routine-family result row: the flat-row form of a routine/template
/// (cards belong to the Routines tab; a search result list reads flat).
/// Name with the match painted, then the "has X" explainer + amber
/// missing-gear capsules.
private struct SearchRoutineRow: View {
    let title: String
    let highlight: [Range<String.Index>]
    let capsules: [CardCapsule]
    var leadingSymbol: String?

    var body: some View {
        HStack(spacing: 10) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(highlightedName(title, ranges: highlight))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !capsules.isEmpty {
                    OverflowCapsuleRow(capsules: capsules)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Theme.textFaint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

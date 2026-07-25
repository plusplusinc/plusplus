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

/// Universal search — "Find or create" (design handoff 2026-07-23; rebuilt
/// 2026-07-25). ONE place to find or make a routine, an exercise, or a piece
/// of equipment, yours or the catalog's. The per-tab header magnifiers retired
/// into this surface; in-picker and pushed-catalog search stay.
///
/// The chrome is the platform's (2026-07-25): the native `.searchable` field
/// morphed from the tab bar by `Tab(role: .search)`, and the scopes as the
/// TabView's bottom ACCESSORY riding above that field (`SearchScopeBar`) —
/// the three catalog tabs the field absorbed, still there to narrow by. Both
/// sit outside this tab's content, so this view owns neither `query` nor
/// `scope`; it reads them as bindings and renders what they select.
///
/// Layout: tab-root header grammar (++ key · title · kit switcher — kit is
/// CONTEXT, never a filter chip) → create row → results.
/// The create row is present unless the query EXACTLY names an item that
/// already exists (a create there would only duplicate the row right below
/// it — `FindOrCreateEngine.Collisions`); it never dead-ends, since an
/// exact-name match always ranks into the results. An EMPTY query shows the
/// scope's WHOLE list, grouped the way its tab groups it (MINE / CATALOG, each
/// with its own collapsible "require more equipment" subgroup) — search opens
/// onto the content you were already looking at, and typing narrows it.
/// Rows are clean (decision A): tap pushes detail onto THIS stack — back
/// returns with the query and scroll intact — and the long-press context menu
/// carries the quick acts. The active kit is the one app-wide pointer,
/// switched only through the tray.
struct FindOrCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    /// Query and scope live in the ROOT (2026-07-25): the scope selector is the
    /// TabView's bottom accessory, which sits outside this tab's content, so
    /// both it and this surface read the same state from above them.
    @Binding var query: String
    @Binding var scope: FindScope
    /// Per-scope match counts, published UP to the accessory's scope labels.
    /// Computed here because this view already holds the catalog queries —
    /// counting at the root would duplicate them app-wide.
    @Binding var counts: [FindScope: Int]

    @State private var path = NavigationPath()
    /// Native search focus. NOT armed on entry (the field must not auto-rise
    /// the keyboard, Dave 2026-07-24) — set true only by the empty-query Kit
    /// create row ("type a name first" = put the cursor back in the field).
    @FocusState private var searchFocused: Bool
    @State private var showingLibraryTray = false
    @State private var creatingExercise = false
    @State private var namingRoutine = false
    @State private var newRoutineName = ""
    /// Which "N <noun>s require more equipment" groups are expanded. Ephemeral
    /// like the query (a stale expansion would be as odd as a stale search) —
    /// reset to collapsed on every entry. Keyed by `Section.id`, one per tier:
    /// "MISSING_MINE" / "MISSING_CATALOG".
    @State private var expandedMissing: Set<String> = []

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
        // An empty query shows the scope's WHOLE list, grouped exactly as its
        // tab groups it (Dave, 2026-07-25) — search opens onto the content you
        // were already looking at, and typing narrows it.
        FindOrCreateEngine.sections(
            query: trimmedQuery,
            scope: scope,
            exercises: allExercises,
            equipment: allEquipment,
            routines: routines,
            templates: RoutineCatalog.all,
            kitNames: kitNames
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
                // No scope control here: the scopes ARE the three catalog tabs,
                // riding above the field as the TabView's bottom accessory
                // (2026-07-25). Kit availability isn't a filter either —
                // un-doable results group under a collapsible "require more
                // equipment" disclosure inside each MINE/CATALOG tier.
                resultsList
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // The NATIVE search field: `.searchable` on the search-role tab
            // morphs the tab bar into the system field (bottom, Liquid Glass),
            // carrying the native clear and Cancel for free. Placement B
            // (searchable INSIDE the search tab's stack) so the prompt can read
            // `scope`; the morph comes from `role: .search`, not from where
            // `.searchable` sits. No `.tabViewSearchActivation` — the native
            // default activates search only on a field tap, so the keyboard
            // does NOT auto-rise on entry (Dave's ask, 2026-07-24).
            // ⚠️ Device-pass: the documented iOS 26 morph bug — an
            // `.onGeometryChange` elsewhere in the TabView subtree (TodayView's
            // onboarding step-height probe) can make the field fall back to the
            // top `.navigationBarDrawer` placement on the FIRST activation. This
            // surface HIDES the nav bar, so that fallback has nowhere to render
            // and the failure reads as NO field. If it recurs, rework the probe
            // at its source (nav-diag 4e), don't revert.
            .searchable(text: $query, prompt: Text(searchPrompt))
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { openTopResult() }
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
        // Ephemeral per-entry state (a stale invisible query reads as data
        // loss): every ENTRY into the tab starts from a blank query with a
        // fresh stack and every missing group collapsed — or onto a pre-scoped
        // launch. Attached to the stack, not the root content, so a pop-back
        // INSIDE the stack does not reset (back returns to live results).
        .onAppear(perform: enterSurface)
        // The labels' counts follow the query. `initial: true` seeds them for a
        // surface opened with a query already in hand (a pre-scoped deep link
        // arrives empty, which correctly counts nothing).
        .onChange(of: trimmedQuery, initial: true) { _, _ in
            counts = FindOrCreateEngine.matchCounts(
                query: trimmedQuery,
                exercises: allExercises,
                equipment: allEquipment,
                routines: routines,
                templates: RoutineCatalog.all,
                kitNames: kitNames
            )
        }
    }

    private func enterSurface() {
        let launch = FindOrCreateLaunch.pending
        FindOrCreateLaunch.pending = nil
        if let launch { scope = launch }
        query = ""
        path = NavigationPath()
        expandedMissing = []      // every entry starts with missing groups collapsed
        // Deliberately no focus arming: the native field stays unfocused on
        // entry, so the keyboard doesn't auto-rise (Dave 2026-07-24).
    }

    /// The native field's placeholder, per scope. The Kit scope searches the
    /// equipment CATALOG, not just your kit, so it reads "Search equipment" —
    /// the single-item/catalog sense of the word (kit-vs-equipment law).
    private var searchPrompt: String {
        "Search \(scope.searchNoun)"
    }

    // MARK: - Results

    private var resultsList: some View {
        // One pass per render, shared by every equipment row ("N exercises").
        let unlockedCounts = exerciseCountsByEquipment
        let collisions = self.collisions
        return List {
            if showsCreateRow(collisions) {
                createRow
            }
            // Real Sections (not loose header rows) so `.listStyle(.plain)`
            // PINS each heading to the top of the scroll area until the next
            // section's heading pushes it up — one sticky heading at a time.
            // A `.missing` section is the collapsible "require more equipment"
            // group: its rows show only when expanded, behind a plain (never
            // pinned) disclosure header row.
            ForEach(sections) { section in
                switch section.kind {
                case .results:
                    Section {
                        ForEach(section.results) { result in
                            resultRow(result, unlockedCounts: unlockedCounts)
                        }
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
    }

    /// Only ever a genuinely empty match now: an empty query shows the whole
    /// scope, and
    /// un-doable items are never hidden (they group under the collapsible
    /// disclosure), so a kit that can do nothing still shows that group rather
    /// than emptying.
    private var emptyState: some View {
        Text("Nothing matches.")
            .font(.system(.footnote))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func toggleMissing(_ id: String) {
        if expandedMissing.contains(id) {
            expandedMissing.remove(id)
        } else {
            expandedMissing.insert(id)
        }
    }

    private func sectionHeaderView(_ section: FindOrCreateEngine.Section) -> some View {
        SheetSectionLabel("\(section.title) · \(section.count)")
            .frame(maxWidth: .infinity, alignment: .leading)
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
            // The modality figure stays: it says what KIND of movement this is,
            // which is information beyond "this row is an exercise" (the type
            // is already given by the scope you're in).
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
                nameHighlight: highlight(equipment.name)
            )
        case .routine(let routine):
            SearchRoutineRow(
                title: routine.name,
                highlight: highlight(routine.name),
                capsules: routineCapsules(
                    matched: result.matchedExerciseName,
                    gear: routine.gearAvailability(activeNames: kitNames)
                )
            )
        case .template(let template):
            SearchRoutineRow(
                title: template.name,
                highlight: highlight(template.name),
                capsules: routineCapsules(
                    matched: result.matchedExerciseName,
                    gear: template.equipmentNames.map { (name: $0, available: kitNames.contains($0)) }
                )
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
    /// Root-only: the field lives in the bottom BAR, outside this stack, so it
    /// stays live and submittable over a pushed detail. Without the guard a
    /// second Return would stack another copy of the same screen —
    /// `path.append` is not idempotent (ui-interaction.md).
    private func openTopResult() {
        guard path.isEmpty, let top = sections.first?.results.first else { return }
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

    /// The create for the scope you're in, unless that exact name already
    /// exists — then the identical item is right there in the results and a
    /// create would only duplicate it.
    private func showsCreateRow(_ collisions: FindOrCreateEngine.Collisions) -> Bool {
        switch scope {
        case .routines:
            return !collisions.routine
        case .exercises:
            return !collisions.exercise
        case .kit:
            return !collisions.equipment
        }
    }

    @ViewBuilder
    private var createRow: some View {
        Group {
            switch scope {
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

    private var routinesCreateLabel: String {
        trimmedQuery.isEmpty ? "New routine" : "New routine \(quotedQuery)"
    }

    private var exercisesCreateLabel: String {
        trimmedQuery.isEmpty ? "New exercise" : "Create \(quotedQuery)"
    }

    private var kitCreateLabel: String {
        trimmedQuery.isEmpty ? "New equipment…" : "Add \(quotedQuery) as equipment"
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
            // "Type a name first": put the cursor back in the field. This is a
            // deliberate user action (they tapped create), so focusing here is
            // not the auto-focus-on-entry the native default avoids.
            searchFocused = true
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

    var body: some View {
        HStack(spacing: 10) {
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

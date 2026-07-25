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
/// It is a MODE, not a tab (2026-07-25). The field and the scope selector live
/// in `AppBottomBar` — activating search expands the field over the Routines /
/// Exercises / Kit tab slots, and those three rise above it as the scopes,
/// carrying their result counts. So this view owns neither: it reads `query`
/// and `scope` as bindings and renders what they select. It is mounted only
/// while searching, which is what makes the state ephemeral by construction.
///
/// Layout: tab-root header grammar (++ key · title · kit switcher — kit is
/// CONTEXT, never a filter chip) → create row → results.
/// The create row is present unless the query EXACTLY names an item that
/// already exists (a create there would only duplicate the row right below
/// it — `FindOrCreateEngine.Collisions`); it never dead-ends, since an
/// exact-name match always ranks into the results. An EMPTY query shows no
/// results at all: this surface finds and creates, and each catalog tab is
/// where you browse its own type — the old everything-index is what made the
/// surface read as a second copy of those tabs.
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

    /// The query, the scope, and the field's focus intent all live in the
    /// ROOT now (2026-07-25) — the field and the scope selector are in the
    /// bottom bar, which outlives this surface, so this view reads them
    /// rather than owning them.
    @Binding var query: String
    @Binding var scope: FindScope
    @Binding var fieldWantsFocus: Bool
    /// Per-scope match counts, published UP to the bar's scope labels. Computed
    /// here because this view already holds the catalog queries — counting at
    /// the root would duplicate them app-wide.
    @Binding var counts: [FindScope: Int]

    @State private var path = NavigationPath()
    @State private var showingLibraryTray = false
    @State private var creatingExercise = false
    @State private var namingRoutine = false
    @State private var newRoutineName = ""
    /// Which "N <noun>s require more equipment" groups are expanded. Ephemeral
    /// like the query (a stale expansion would be as odd as a stale search) —
    /// reset to collapsed on every entry. Keyed by `Section.id`
    /// ("MISSING_ROUTINES"/"MISSING_EXERCISES" in All scope, "MISSING" scoped).
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
        // No query, no results. This surface finds and creates; browsing a
        // type is what that type's TAB is for — showing everything here is
        // exactly what made search read as a second copy of those tabs
        // (2026-07-25). The engine can still rank an empty query; we just
        // don't ask it to.
        guard !trimmedQuery.isEmpty else { return [] }
        return FindOrCreateEngine.sections(
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
                // No scope control here any more: the scopes ARE the three
                // catalog tabs, riding above the field in the bottom bar
                // (2026-07-25). Kit availability isn't a filter either —
                // un-doable results group under a collapsible "require more
                // equipment" disclosure in the list.
                resultsList
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // The field itself is in `AppBottomBar` — it has to be, since it
            // expands over the tab slots. Its Return key reaches the ranked
            // results through a notification rather than a closure.
            .onReceive(NotificationCenter.default.publisher(for: .plusplusOpenTopResult)) { _ in
                openTopResult()
            }
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
        // The surface is mounted only while searching, so this fires once per
        // search: a fresh stack with every missing group collapsed. The query
        // and scope belong to the bar and are already set by the time we mount.
        .onAppear {
            path = NavigationPath()
            expandedMissing = []
        }
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
        // Leaving search takes the numbers with it — a count on a resting tab
        // label would be a leftover from a query that's no longer on screen.
        .onDisappear { counts = [:] }
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

    /// Two quiet states, never a wall of everything: before a query there is
    /// nothing to show (this surface finds and creates — each tab is where you
    /// BROWSE its own type), and after one that matches nothing, the miss is
    /// stated plainly. Un-doable items are never hidden — they group under the
    /// collapsible disclosure — so a kit that can do nothing still shows that
    /// group rather than emptying.
    private var emptyState: some View {
        // No possessive: every scope searches YOURS AND the catalog, so "your
        // exercises" would be false (and exercises have no library at all).
        Text(trimmedQuery.isEmpty
             ? "Search \(scope.searchNoun), or make something new."
             : "Nothing matches.")
            .font(.system(.footnote))
            .foregroundStyle(Theme.textFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
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
            // "Type a name first": put the cursor back in the field (which now
            // lives in the bottom bar, so the intent travels through its
            // one-shot focus binding).
            fieldWantsFocus = true
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

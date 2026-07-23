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
/// is CONTEXT, never a filter chip) → the shared search-field anatomy +
/// a text Done key (never ✕) → scope chips → create row → results.
/// The create row is ALWAYS present (never a dead end); an empty query
/// shows everything, mine-first. Rows are clean (decision A): tap pushes
/// detail onto THIS stack — back returns with query, scope, and scroll
/// intact — and the long-press context menu carries the quick acts.
/// Search state is ephemeral per-entry; the active kit is the one
/// app-wide pointer, switched only through the tray.
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
                fieldRow
                scopeChips
                resultsList
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
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

    private var fieldRow: some View {
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
            // A text dismiss key (the sheet-dismissal grammar) — never ✕,
            // which means collapse-search everywhere.
            SheetDismissKey(identifier: "findOrCreateDone", action: onDone)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                scopeChip(.all, "All", nil)
                scopeChip(.routines, "Routines", "checklist")
                scopeChip(.exercises, "Exercises", "figure.strengthtraining.traditional")
                scopeChip(.kit, "Kit", "dumbbell")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 2)
    }

    private func scopeChip(_ target: FindScope, _ label: String, _ symbol: String?) -> some View {
        SelectableChip(
            label: label,
            isSelected: scope == target,
            identifier: "findScope-\(target.rawValue)",
            systemImage: symbol
        ) {
            scope = target
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        // One pass per render, shared by every equipment row ("N exercises").
        let unlockedCounts = exerciseCountsByEquipment
        return List {
            createRow
            ForEach(sections) { section in
                sectionHeader(section)
                ForEach(section.results) { result in
                    resultRow(result, unlockedCounts: unlockedCounts)
                }
                if section.moreCount > 0 {
                    moreRow(section)
                }
            }
            if sections.isEmpty {
                Text("Nothing matches.")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func sectionHeader(_ section: FindOrCreateEngine.Section) -> some View {
        Group {
            if let target = section.scopeTarget {
                // An All-scope section header is a door into its scope —
                // same jump as the more-row beneath it.
                Button {
                    scope = target
                } label: {
                    SheetSectionLabel("\(section.title) · \(section.count)")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                SheetSectionLabel("\(section.title) · \(section.count)")
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 2, trailing: 16))
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

    private var createRow: some View {
        Group {
            switch scope {
            case .all:
                CreateMenuRow(label: allCreateLabel, identifier: "findCreateMenu") {
                    createChooserItems
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
    @ViewBuilder
    private var createChooserItems: some View {
        Button {
            creatingExercise = true
        } label: {
            Label(trimmedQuery.isEmpty ? "New exercise" : "Create exercise \(quotedQuery)",
                  systemImage: "figure.strengthtraining.traditional")
        }
        Button {
            createRoutineFromQuery()
        } label: {
            Label(trimmedQuery.isEmpty ? "New routine" : "New routine \(quotedQuery)",
                  systemImage: "checklist")
        }
        if !trimmedQuery.isEmpty {
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

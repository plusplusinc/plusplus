import SwiftUI
import SwiftData
import PlusPlusKit

/// The equipment catalog, rebuilt as a browse-into surface (2026-07-17,
/// replacing CatalogBrowseScreen's equipment kind): every row is a card
/// you tap INTO — the redesigned detail is where you configure gear and
/// add it to your kit — and a leading swipe-right is the quick add for
/// gear that needs no configuring. Pick, tune, keep moving.
///
/// Filters: a KIT facet (In kit / Not), a MUSCLE tray (gear ranked by
/// what it lets you train, from the same exercise index that feeds the
/// "N exercises" capsules), and five inline type chips backed by
/// `SeedData.equipmentCategories` (app-side static table; customs carry
/// no category and drop out under a type chip).
///
/// Setup mode (the Today onboarding step + the Settings re-run) keeps
/// the pinned Done bar, the swipe-back parity, and the populate offer
/// exactly as the old browse had them — quick-adds and detail visits
/// count as engagement.
struct EquipmentCatalogScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    /// §F: onboarding + the Settings re-run ride the REAL catalog with
    /// a pinned confirm bar — the limited tray (and the preset strip,
    /// #203) died.
    var setupMode = false

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// Search text + muscle selection ride the shared filter state so
    /// MuscleGroupFilterSheet works unmodified.
    @State private var filterState = ExerciseFilterState()
    /// nil = All · true = In kit · false = Not in kit.
    @State private var kitFilter: Bool?
    /// Multi-select TYPE facet in a tray now (2026-07-17 feedback: one
    /// filter-row vocabulary — the inline type chips were a second chip
    /// shape next to the mono facet chips, which read as uneven spacing).
    /// Union within the facet; categories don't overlap, so union reads
    /// as "any of these types".
    @State private var typeFilter: Set<SeedData.EquipmentCategory> = []
    @State private var showingTypeFilter = false
    @State private var showingMuscleFilter = false
    /// Alphabetical by default, or by how many exercises the gear unlocks
    /// (Dave's ask — the count is a sortable property, not just a capsule).
    @State private var sortOrder: EquipmentSort = .name
    /// Detail push — an ITEM destination on this screen deliberately
    /// (#291): the browse itself is presented as a boolean/isPresented
    /// destination from the tabs, Today's setup step, the reveal
    /// surface, and sheet-local stacks; a VALUE append beneath a live
    /// boolean destination breaks back-pop, while a boolean/item
    /// destination ON TOP is legal everywhere. Do not convert this to
    /// `path.append`.
    @State private var pushedEquipment: Equipment?
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    /// Custom gear is just a name, so an empty-query create prompts for
    /// one here instead of silently doing nothing (#170).
    @State private var promptingEquipmentName = false
    @State private var newEquipmentName = ""
    /// Any engagement (quick-add, membership change, detail visit)
    /// counts: plain back then still marks setup done (never trap the
    /// user in a step).
    @State private var touchedSetup = false
    /// The active-kit switcher opens here too (2026-07-20): the catalog is
    /// where you ADD, so the target kit has to be nameable + switchable
    /// without backing out to the Kit tab.
    @State private var showingLibraryTray = false

    /// `initialQuery` seeds the search once (the Equipment-kit tab's "Add
    /// <query>" threads its query straight through, 2026-07-18); the pushed
    /// chrome auto-expands the field when it arrives non-empty.
    init(setupMode: Bool = false, initialQuery: String = "") {
        self.setupMode = setupMode
        let state = ExerciseFilterState()
        state.searchText = initialQuery
        self._filterState = State(initialValue: state)
    }

    private var query: String { filterState.searchText }

    private var availableNames: Set<String> {
        activeLibrary?.memberNames ?? []
    }

    /// One pass over the catalog graph per body evaluation: how many
    /// exercises each gear unlocks, and which muscle groups those
    /// exercises train. Feeds the row capsules AND the muscle facet —
    /// the old browse re-scanned all exercises per row.
    private var exerciseIndex: [PersistentIdentifier: (count: Int, muscles: Set<MuscleGroup>)] {
        var index: [PersistentIdentifier: (count: Int, muscles: Set<MuscleGroup>)] = [:]
        // ALL exercises, customs included — the Equipment tab's counts
        // do the same, and a muscle filter must not hide gear whose
        // only exercises are the user's own.
        for exercise in allExercises {
            for gear in exercise.equipment {
                var entry = index[gear.persistentModelID] ?? (0, [])
                entry.count += 1
                entry.muscles.insert(exercise.muscleGroup)
                index[gear.persistentModelID] = entry
            }
        }
        return index
    }

    private var anyFilterActive: Bool {
        kitFilter != nil || !typeFilter.isEmpty || !filterState.selectedMuscleGroups.isEmpty
    }

    /// The active facets, summarized for the filter-state popover.
    private var activeFacets: [ActiveFacet] {
        var facets: [ActiveFacet] = []
        if let kitFilter {
            facets.append(ActiveFacet(name: "Kit", value: kitFilter ? "In kit" : "Not in kit"))
        }
        if !typeFilter.isEmpty {
            facets.append(ActiveFacet(name: "Type", value: typeFilter.map(\.rawValue).sorted().joined(separator: ", ")))
        }
        if !filterState.selectedMuscleGroups.isEmpty {
            let names = filterState.selectedMuscleGroups.map(\.displayName).sorted().joined(separator: ", ")
            facets.append(ActiveFacet(name: "Muscle", value: names))
        }
        return facets
    }

    var body: some View {
        let index = exerciseIndex
        VStack(spacing: 0) {
            // Onboarding is a guided single-kit setup with its own Done
            // bar; a switch-kits control there is out of place. Everywhere
            // else, name the kit these adds land in (Dave, 2026-07-20).
            if !setupMode {
                activeKitBar
            }
            filterRow
            List {
                // Creation is the top row everywhere (2026-07-18): New
                // equipment, or Create "<query>" when searching.
                createRow
                ForEach(candidateEquipment(index: index)) { equipment in
                    equipmentCard(equipment, index: index)
                }
                if candidateEquipment(index: index).isEmpty {
                    emptyResults
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .padding(.top, 2)
        }
        .background(Theme.background)
        .pushedScreenChrome(
            title: "Equipment catalog",
            search: HeaderSearchConfig(
                text: Bindable(filterState).searchText,
                prompt: "Search the catalog",
                identifier: "catalogSearchField"
            ),
            onBack: { dismiss() }
        )
        // Rightward row drags open the quick-add, so the full-width
        // back-swipe narrows to the edge band here — and hands full
        // width back the moment detail is pushed.
        .leadingRevealHost(active: pushedEquipment == nil)
        .navigationDestination(item: $pushedEquipment) { equipment in
            // Setup context strips the detail to add + configure (Dave,
            // 2026-07-17): the exercises/routines cross-links distract from
            // the onboarding task. The Equipment tab keeps the full graph.
            EquipmentDetailScreen(equipment: equipment, isOnboarding: setupMode)
        }
        .safeAreaInset(edge: .bottom) {
            if setupMode {
                Button {
                    touchedSetup = true
                    SetupState.markEquipmentDone()
                    dismiss()
                } label: {
                    Text(availableNames.isEmpty ? "Done · bodyweight only" : "Done · \(availableNames.count) item\(availableNames.count == 1 ? "" : "s")")
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
        }
        .onDisappear {
            // Plain back after engaging still counts as done — never
            // trap the user in a setup step (§F).
            if setupMode && touchedSetup && !SetupState.equipmentDone {
                SetupState.markEquipmentDone()
            }
        }
        // Membership changes + catalog adds reach GitHub when the browse
        // surface closes. Debounced + dirty-gated (see requestSync).
        .syncsProgramOnClose()
        .alert("New equipment", isPresented: $promptingEquipmentName) {
            TextField("Name", text: $newEquipmentName)
            Button("Create") {
                let name = newEquipmentName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { createEquipment(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingTypeFilter) {
            EquipmentTypeFilterSheet(selection: $typeFilter)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMuscleFilter) {
            MuscleGroupFilterSheet(filterState: filterState)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingLibraryTray) {
            EquipmentLibraryTray()
        }
    }

    // MARK: - Active kit

    /// The null kit is immutable — nothing lands in it — so the strip's verb
    /// and the row swipes below reflect that.
    private var activeIsBodyweight: Bool { activeLibrary?.isBodyweight ?? false }

    /// Which kit these adds land in, named and switchable right here (Dave,
    /// 2026-07-20): the catalog is the ADD surface, but the active kit was
    /// only legible back on the Kit tab, so a run of quick-adds could pour
    /// into the wrong kit unnoticed. Reuses the tab's `LibrarySwitcherKey`;
    /// switching re-renders the cards' in-kit glyphs behind the tray.
    private var activeKitBar: some View {
        HStack(spacing: 8) {
            Text(activeIsBodyweight ? "On" : "Adding to")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
            LibrarySwitcherKey(
                name: activeLibrary?.name ?? EquipmentLibrary.defaultName,
                identifier: "catalogKitSwitcher"
            ) {
                showingLibraryTray = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if anyFilterActive {
                    FilterSummaryChip(
                        facets: activeFacets,
                        onClearAll: {
                            kitFilter = nil
                            typeFilter = []
                            filterState.selectedMuscleGroups = []
                        }
                    )
                }
                FacetChip(
                    facet: "Kit",
                    selection: $kitFilter,
                    options: [(true, "In kit"), (false, "Not in kit")],
                    attributeSymbol: "dumbbell.fill",
                    valueSymbols: [true: "checkmark.circle.fill", false: "circle"]
                )
                TrayFilterChip(
                    facet: "Type",
                    count: typeFilter.count,
                    activeSymbol: "tag.fill"
                ) { showingTypeFilter = true }
                TrayFilterChip(
                    facet: "Muscle",
                    count: filterState.selectedMuscleGroups.count,
                    activeSymbol: "figure.arms.open"
                ) { showingMuscleFilter = true }
                SortChip(
                    selection: $sortOrder,
                    options: [(.name, "Name"), (.mostExercises, "Most exercises")]
                )
                Spacer(minLength: 0)
            }
            .animation(Theme.Anim.standard, value: anyFilterActive)
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
    }

    // MARK: - Candidates

    private func candidateEquipment(index: [PersistentIdentifier: (count: Int, muscles: Set<MuscleGroup>)]) -> [Equipment] {
        // Forgiving search, best match first (blank passes all through
        // in @Query's alphabetical order).
        let matched = FuzzySearch.ranked(allEquipment, query: query) { $0.name }
            .filter { equipment in
                if let kitFilter, (activeLibrary?.contains(equipment) ?? false) != kitFilter {
                    return false
                }
                if !typeFilter.isEmpty {
                    guard let category = SeedData.equipmentCategory(named: equipment.name),
                          typeFilter.contains(category) else { return false }
                }
                if !filterState.selectedMuscleGroups.isEmpty {
                    let trained = index[equipment.persistentModelID]?.muscles ?? []
                    if trained.isDisjoint(with: filterState.selectedMuscleGroups) {
                        return false
                    }
                }
                return true
            }
        switch sortOrder {
        case .name:
            // Leave the search rank (best-match-first when searching,
            // alphabetical when blank) — the default order is unchanged.
            return matched
        case .mostExercises:
            return matched.sorted {
                let a = index[$0.persistentModelID]?.count ?? 0
                let b = index[$1.persistentModelID]?.count ?? 0
                return a != b ? a > b : $0.name < $1.name
            }
        }
    }

    // MARK: - Rows

    private func equipmentCard(_ equipment: Equipment, index: [PersistentIdentifier: (count: Int, muscles: Set<MuscleGroup>)]) -> some View {
        let inKit = activeLibrary?.contains(equipment) ?? false
        let unlocked = index[equipment.persistentModelID]?.count ?? 0
        return SwipeRevealRow(
            id: equipment.persistentModelID,
            openRow: $openSwipeRow,
            actionsWidth: 0,
            leadingActionsWidth: activeIsBodyweight ? 0 : 58,
            onTap: {
                touchedSetup = true
                pushedEquipment = equipment
            },
            accessibilityActions: activeIsBodyweight ? [] : [
                SwipeRowAction(name: inKit ? "Remove from kit" : "Add to kit") {
                    openSwipeRow = nil
                    setMembership(equipment, !inKit)
                }
            ]
        ) {
            // Shared representation (2026-07-18): the catalog card and the
            // kit list render the same body; the catalog shows the in-kit
            // glyph, the kit list omits it (every row is in the kit there).
            EquipmentRowContent(equipment: equipment, unlockedCount: unlocked, inKit: inKit)
        } actions: {
            EmptyView()
        } leadingActions: {
            // Quick add: green = creation (#202). Flips to membership
            // removal when already in the kit, so setup keeps
            // toggle-off parity with the old browse. The null kit is
            // immutable, so it has no add/remove swipe.
            // Unique per-row identifier: every realized row's hidden
            // action lives in the accessibility tree (opacity 0
            // removes nothing — the component's own law), so a bare
            // "ADD" query matches a dozen rows at once. The
            // `toggle-\(name)` precedent.
            if !activeIsBodyweight {
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
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
    }

    private func setMembership(_ equipment: Equipment, _ included: Bool) {
        activeLibrary?.setMembership(equipment, included)
        touchedSetup = true
    }

    // MARK: - Create + empty

    private var createLabel: String {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? "New equipment" : "Create \u{201C}\(q.sentenceCasedFirst)\u{201D}"
    }

    /// Empty results never dead-end: the create row is always at the top
    /// (so "not here" becomes "make it"), and Clear filters is the escape.
    private var emptyResults: some View {
        VStack(spacing: 10) {
            Text("Nothing matches.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
            if anyFilterActive {
                QuietKey(label: "Clear filters", identifier: "clearEquipmentFilters") {
                    kitFilter = nil
                    typeFilter = []
                    filterState.selectedMuscleGroups = []
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var createRow: some View {
        CreateRow(label: createLabel, identifier: "createEquipmentRow") {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                newEquipmentName = ""
                promptingEquipmentName = true
                return
            }
            createEquipment(named: trimmed)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    /// Creating custom gear adds it to the active kit and pushes its
    /// detail — configure it right away, then keep moving. The
    /// synchronous save is load-bearing (swiftdata.md): the push keys on
    /// `persistentModelID`, and presenting a model whose ID is still
    /// temporary re-keys the push at the next autosave (the tray
    /// flicker).
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
        pushedEquipment = item
    }
}

/// Catalog sort (2026-07-17): alphabetical, or by how many exercises the
/// gear unlocks. Ordering is not filter state, so it rides the neutral
/// `SortChip` in the same row.
enum EquipmentSort: Hashable {
    case name
    case mostExercises
}

/// The TYPE facet's tray, modeled on `MuscleGroupFilterSheet` (2026-07-17
/// feedback: the type filter moved off the inline chip row into a single
/// tray trigger, so the whole filter row speaks one chip vocabulary).
/// Multi-select; categories don't overlap, so the selection reads as "any
/// of these types".
struct EquipmentTypeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<SeedData.EquipmentCategory>

    /// Clear appears only while a selection exists (v4 §C table).
    private var clearAction: (() -> Void)? {
        selection.isEmpty ? nil : { selection.removeAll() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "Equipment type",
                onCancel: clearAction,
                cancelLabel: "Clear",
                action: { dismiss() }
            )
            .padding(.horizontal, 18)
            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(SeedData.EquipmentCategory.allCases, id: \.self) { category in
                        SelectableChip(
                            label: category.rawValue,
                            isSelected: selection.contains(category)
                        ) {
                            if selection.contains(category) {
                                selection.remove(category)
                            } else {
                                selection.insert(category)
                            }
                        }
                    }
                }
                .padding(.vertical)
                .padding(.horizontal, 18)
            }
        }
        .presentationBackground(Theme.surface)
    }
}

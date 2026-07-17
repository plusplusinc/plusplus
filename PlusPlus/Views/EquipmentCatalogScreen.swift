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
    /// Only Today's onboarding step offers population on Done (#204) —
    /// Settings/Library re-runs are curation, not setup.
    var offersPopulateOnDone = false

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// Search text + muscle selection ride the shared filter state so
    /// MuscleGroupFilterSheet works unmodified.
    @State private var filterState = ExerciseFilterState()
    /// nil = All · true = In kit · false = Not in kit.
    @State private var kitFilter: Bool?
    /// Single-select type chip; categories don't overlap.
    @State private var typeFilter: SeedData.EquipmentCategory?
    @State private var showingMuscleFilter = false
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
        kitFilter != nil || typeFilter != nil || !filterState.selectedMuscleGroups.isEmpty
    }

    var body: some View {
        let index = exerciseIndex
        VStack(spacing: 0) {
            filterRow
            List {
                ForEach(candidateEquipment(index: index)) { equipment in
                    equipmentCard(equipment, index: index)
                }
                if candidateEquipment(index: index).isEmpty {
                    Text("Nothing matches these filters.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                createRow
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
            EquipmentDetailScreen(equipment: equipment)
        }
        .safeAreaInset(edge: .bottom) {
            if setupMode {
                Button {
                    touchedSetup = true
                    SetupState.markEquipmentDone()
                    // Population stays the user's call (#185), but the
                    // ask moved to Today (#204) — a popover here floated
                    // anchored to nothing while the screen was leaving.
                    if offersPopulateOnDone {
                        SetupState.requestPopulateOffer()
                    }
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
            // trap the user in a setup step (§F). And the exits must be
            // EQUIVALENT: the swipe-back that marks done also carries
            // the populate offer the Done button would have (FTUE
            // audit — the offer had no re-ask anywhere).
            if setupMode && touchedSetup && !SetupState.equipmentDone {
                SetupState.markEquipmentDone()
                if offersPopulateOnDone {
                    SetupState.requestPopulateOffer()
                }
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
        .sheet(isPresented: $showingMuscleFilter) {
            MuscleGroupFilterSheet(filterState: filterState)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if anyFilterActive {
                    ClearAllChip {
                        kitFilter = nil
                        typeFilter = nil
                        filterState.selectedMuscleGroups = []
                    }
                }
                FacetChip(
                    facet: "KIT",
                    selection: $kitFilter,
                    options: [(true, "In kit"), (false, "Not in kit")]
                )
                TrayFilterChip(
                    facet: "MUSCLE",
                    count: filterState.selectedMuscleGroups.count
                ) { showingMuscleFilter = true }
                ForEach(SeedData.EquipmentCategory.allCases, id: \.self) { category in
                    SelectableChip(
                        label: category.rawValue,
                        isSelected: typeFilter == category
                    ) {
                        typeFilter = typeFilter == category ? nil : category
                    }
                }
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
        FuzzySearch.ranked(allEquipment, query: query) { $0.name }
            .filter { equipment in
                if let kitFilter, (activeLibrary?.contains(equipment) ?? false) != kitFilter {
                    return false
                }
                if let typeFilter, SeedData.equipmentCategory(named: equipment.name) != typeFilter {
                    return false
                }
                if !filterState.selectedMuscleGroups.isEmpty {
                    let trained = index[equipment.persistentModelID]?.muscles ?? []
                    if trained.isDisjoint(with: filterState.selectedMuscleGroups) {
                        return false
                    }
                }
                return true
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
            leadingActionsWidth: 58,
            onTap: {
                touchedSetup = true
                pushedEquipment = equipment
            },
            accessibilityActions: [
                SwipeRowAction(name: inKit ? "Remove from kit" : "Add to kit") {
                    openSwipeRow = nil
                    setMembership(equipment, !inKit)
                }
            ]
        ) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(equipment.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    subtitle(for: equipment, inKit: inKit)
                        .font(.system(.caption))
                        .lineLimit(1)
                }
                Spacer()
                if unlocked > 0 {
                    Text("\(unlocked) exercise\(unlocked == 1 ? "" : "s")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Theme.border))
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        } actions: {
            EmptyView()
        } leadingActions: {
            // Quick add: green = creation (#202). Flips to membership
            // removal when already in the kit, so setup keeps
            // toggle-off parity with the old browse.
            SwipeActionButton(
                label: inKit ? "REMOVE" : "ADD",
                color: inKit ? Theme.destructive : Theme.accent
            ) {
                openSwipeRow = nil
                setMembership(equipment, !inKit)
            }
        }
        .accessibilityIdentifier("equipmentCard-\(equipment.name)")
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
    }

    private func subtitle(for equipment: Equipment, inKit: Bool) -> Text {
        var parts: [Text] = []
        if let category = SeedData.equipmentCategory(named: equipment.name) {
            parts.append(Text(category.rawValue).foregroundStyle(Theme.textSecondary))
        }
        if !equipment.isBuiltIn {
            parts.append(Text("Custom").foregroundStyle(Theme.textSecondary))
        }
        if inKit {
            parts.append(Text("in kit ✓").foregroundStyle(Theme.accent))
        }
        guard var text = parts.first else {
            return Text(" ").foregroundStyle(Theme.textSecondary)
        }
        for part in parts.dropFirst() {
            text = text + Text(" · ").foregroundStyle(Theme.textFaint) + part
        }
        return text
    }

    private func setMembership(_ equipment: Equipment, _ included: Bool) {
        activeLibrary?.setMembership(equipment, included)
        touchedSetup = true
    }

    // MARK: - Create

    private var createRow: some View {
        Button {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                newEquipmentName = ""
                promptingEquipmentName = true
                return
            }
            createEquipment(named: trimmed)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(.caption, weight: .semibold))
                Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Create custom equipment…"
                     : "Create “\(query.trimmingCharacters(in: .whitespaces))”")
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            // Creation is green (#202).
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("createEquipmentRow")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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

import SwiftUI
import SwiftData
import PlusPlusKit

/// The Exercises tab IS the whole catalog now (2026-07-17): an exercise
/// is a thing you choose to do, not a thing you own, so there is no
/// library to fill — every exercise is listed, always, narrowed by
/// persistent filters (favorites, gear availability, muscle) and curated
/// by favoriting. Rows favorite on a leading swipe, delete customs on a
/// trailing swipe, and tap into detail. Replaces the old two-surface
/// library + `CatalogBrowseScreen` split.
struct ExercisesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    // Persisted filters (device-local; the tab is the source of truth
    // during a session and mirrors to these).
    @AppStorage(ExerciseFilterState.Prefs.favoritesOnly) private var prefFavoritesOnly = false
    @AppStorage(ExerciseFilterState.Prefs.muscleGroups) private var prefMuscleGroups = "[]"

    @State private var filterState = ExerciseFilterState()
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    @State private var path = NavigationPath()
    @State private var showingMuscleFilter = false
    @State private var creatingExercise = false
    /// Whether the "N exercises require more equipment" group is expanded
    /// (collapsed by default; ephemeral, like the whole catalog view).
    @State private var showMissingExercises = false
    @State private var loadedPrefs = false
    @State private var showingLibraryTray = false
    /// The row playing the entrance flash after a cross-tab create
    /// (`ExerciseArrival`); scroll + ring identity, cleared by the task.
    @State private var newlyAdded: PersistentIdentifier?

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    /// The raw kit name — a control label, so it always names the kit
    /// (the one-rule naming law; prose uses `activeNamePhrase`).
    private var activeKitName: String {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.name ?? EquipmentLibrary.defaultName
    }

    private var candidates: [Exercise] {
        filterState.filteredExercises(from: allExercises, kitNames: availableEquipmentNames)
    }

    /// The catalog split into what the active kit can do and what needs more
    /// equipment (2026-07-25). Both keep `candidates`' rank/sort order; the
    /// missing ones tuck under a collapsible group rather than being hidden.
    private var doableCandidates: [Exercise] {
        candidates.filter {
            ExerciseFilterState.missingEquipment(for: $0, available: availableEquipmentNames).isEmpty
        }
    }

    private var missingCandidates: [Exercise] {
        candidates.filter {
            !ExerciseFilterState.missingEquipment(for: $0, available: availableEquipmentNames).isEmpty
        }
    }

    private var anyFilterActive: Bool {
        filterState.favoritesOnly
            || !filterState.selectedMuscleGroups.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // The header magnifier retired into the universal Find-or-
                // create surface (2026-07-23); the filter row below is this
                // tab's remaining narrowing.
                CatalogTabHeader(title: "Exercises") {
                    // Switch the kit exercises are judged against, inline
                    // (2026-07-21 axes separation) — the same switcher the Kit
                    // tab and routine catalog use. It's what decides which rows
                    // fall into the "require more equipment" group below.
                    LibrarySwitcherKey(name: activeKitName, identifier: "exercisesKitSwitcher") {
                        showingLibraryTray = true
                    }
                }
                filterRow
                ScrollViewReader { proxy in
                    List {
                        // Creation is the top row everywhere (2026-07-18): New
                        // exercise, or Create "<query>" when searching.
                        createExerciseRow
                        ForEach(doableCandidates) { exercise in
                            exerciseRow(exercise)
                        }
                        // What the active kit can't do, tucked under a
                        // collapsible disclosure AFTER the doable rows
                        // (2026-07-25). Collapsed by default; the rows still
                        // carry their own amber "needs X" tags when expanded.
                        if !missingCandidates.isEmpty {
                            MissingEquipmentHeaderRow(
                                count: missingCandidates.count,
                                noun: "exercise",
                                isExpanded: showMissingExercises,
                                identifier: "missingEquipmentToggle-exercises"
                            ) {
                                withAnimation(Theme.Anim.standard) { showMissingExercises.toggle() }
                            }
                            if showMissingExercises {
                                ForEach(missingCandidates) { exercise in
                                    exerciseRow(exercise)
                                }
                            }
                        }
                        if doableCandidates.isEmpty && missingCandidates.isEmpty {
                            emptyResults
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                    // The arrival beat: scroll the landed row into view, let
                    // its ring flash, then clear. Cancellation (tab left, a
                    // superseding arrival) bails without clearing.
                    .task(id: newlyAdded) {
                        guard let target = newlyAdded else { return }
                        do {
                            try await Task.sleep(for: .milliseconds(80))
                            withAnimation(Theme.Anim.standard) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                            try await Task.sleep(for: .seconds(2.2))
                            newlyAdded = nil
                        } catch {}
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
            .sheet(isPresented: $creatingExercise) {
                ExerciseEditorView(prefillMuscleGroup: filterState.prefillMuscleGroup)
            }
            .sheet(isPresented: $showingMuscleFilter) {
                MuscleGroupFilterSheet(filterState: filterState)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingLibraryTray) {
                EquipmentLibraryTray()
            }
        }
        .revealRoot(tab: "exercises", atRoot: path.isEmpty)
        // Favorites + custom deletes reach GitHub when you leave the tab.
        // The landing may arrive while this tab is unmounted (the root
        // switches tabs on the same notification) — consume on receive
        // AND on appear, whichever fires first (the RoutineArrival shape).
        .onReceive(NotificationCenter.default.publisher(for: .plusplusExerciseArrived)) { _ in
            consumeArrival()
        }
        .onAppear {
            // Prefs load BEFORE the arrival consumes: on a first mount
            // caused by the arrival itself, the other order re-applied the
            // persisted filters right after consumeArrival cleared them,
            // re-hiding the row it landed (swift-reviewer catch). The
            // clears then flow back through the onChange mirrors, so the
            // cleared state also persists.
            if !loadedPrefs {
                loadedPrefs = true
                loadPrefs()
            }
            consumeArrival()
        }
        // Mirror in-session filter changes back to storage.
        .onChange(of: filterState.favoritesOnly) { persistPrefs() }
        .onChange(of: filterState.selectedMuscleGroups) { persistPrefs() }
    }

    // MARK: - Create row + empty state

    /// The whole catalog is here, so an empty list is only ever a zeroed
    /// filter — the create row (always at the top) turns "not here" into
    /// "make it", and Clear filters is the escape. Never a dead end.
    private var createExerciseRow: some View {
        CreateRow(label: "New exercise", identifier: "createExerciseRow") {
            creatingExercise = true
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Text("Nothing matches.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
            if anyFilterActive {
                QuietKey(label: "Clear filters", identifier: "clearExerciseFilters") {
                    filterState.favoritesOnly = false
                    filterState.selectedMuscleGroups = []
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if anyFilterActive {
                    FilterSummaryChip(
                        facets: activeFacets,
                        resultSummary: "\(candidates.count) of \(allExercises.count) shown",
                        onClearAll: {
                            filterState.favoritesOnly = false
                            filterState.selectedMuscleGroups = []
                        }
                    )
                }
                SelectableChip(label: "Favorites", isSelected: filterState.favoritesOnly) {
                    filterState.favoritesOnly.toggle()
                }
                // Kit availability is no longer a filter (2026-07-25): what the
                // kit can't do groups under the collapsible "require more
                // equipment" disclosure in the list below, not a facet here.
                TrayFilterChip(
                    facet: "Muscle",
                    count: filterState.selectedMuscleGroups.count
                ) { showingMuscleFilter = true }
                Spacer(minLength: 0)
            }
            .animation(Theme.Anim.standard, value: anyFilterActive)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    /// The active facets, summarized for the filter-state popover
    /// (persisted filters made a silently-narrowed catalog possible —
    /// this is where the narrowing explains itself).
    private var activeFacets: [ActiveFacet] {
        var facets: [ActiveFacet] = []
        if filterState.favoritesOnly {
            facets.append(ActiveFacet(name: "Favorites", value: "Only favorites"))
        }
        if !filterState.selectedMuscleGroups.isEmpty {
            let names = filterState.selectedMuscleGroups.map(\.displayName).sorted().joined(separator: ", ")
            facets.append(ActiveFacet(name: "Muscle", value: names))
        }
        return facets
    }

    // MARK: - Rows

    private func exerciseRow(_ exercise: Exercise) -> some View {
        SwipeRevealRow(
            id: exercise.persistentModelID,
            openRow: $openSwipeRow,
            // Trailing DELETE only for customs; built-ins can't be deleted.
            actionsWidth: exercise.isBuiltIn ? 0 : 58,
            leadingActionsWidth: 58,
            onTap: { path.append(exercise) },
            accessibilityActions: accessibilityActions(exercise)
        ) {
            // Shared representation (2026-07-18): the catalog row and the
            // picker render the same body; the picker drops the chevron.
            ExerciseRowContent(exercise: exercise, available: availableEquipmentNames)
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
            // Favorite is creation-of-yours → green; toggles off to a
            // neutral UNFAVORITE when already lit.
            SwipeActionButton(
                label: exercise.isFavorite ? "UNFAV" : "FAV",
                color: exercise.isFavorite ? Theme.textFaint : Theme.accent,
                identifier: "favSwipe-\(exercise.name)"
            ) {
                openSwipeRow = nil
                exercise.isFavorite.toggle()
            }
        }
        .overlay {
            if newlyAdded == exercise.persistentModelID {
                RowEntranceFlash()
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
    }

    /// Land a cross-tab create: clear whatever would hide the new row
    /// (persisted filters CAN hide a fresh custom — a landing that
    /// flashes an invisible row would be a lie), pop to the root, and
    /// arm the scroll + flash.
    private func consumeArrival() {
        guard let pending = ExerciseArrival.pending else { return }
        ExerciseArrival.pending = nil
        filterState.searchText = ""
        filterState.favoritesOnly = false
        filterState.selectedMuscleGroups = []
        // A fresh custom that needs gear lands in the missing group — expand
        // it so its entrance flash isn't playing on a collapsed row.
        showMissingExercises = true
        path = NavigationPath()
        newlyAdded = pending
    }

    private func accessibilityActions(_ exercise: Exercise) -> [SwipeRowAction] {
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


    // MARK: - Filter persistence

    private func loadPrefs() {
        filterState.favoritesOnly = prefFavoritesOnly
        filterState.selectedMuscleGroups = Set(
            decodeNames(prefMuscleGroups).compactMap(MuscleGroup.init(rawValue:))
        )
    }

    private func persistPrefs() {
        prefFavoritesOnly = filterState.favoritesOnly
        prefMuscleGroups = encodeNames(Set(filterState.selectedMuscleGroups.map(\.rawValue)))
    }

    private func decodeNames(_ json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(array)
    }

    private func encodeNames(_ names: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(names.sorted()),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }
}

/// The Equipment tab (#109): the gear you have in the ACTIVE equipment
/// library. Feeds exercise filtering; the onboarding picker (#113) and
/// the tray switcher write this same list. Switching libraries here
/// re-renders every availability-driven surface in the app.
struct EquipmentTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    @State private var showingLibraryTray = false
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    @State private var path = NavigationPath()
    /// The row playing the entrance flash after a cross-tab add
    /// (`EquipmentArrival`); scroll + ring identity, cleared by the task.
    @State private var newlyAdded: PersistentIdentifier?

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// The baked-in null kit is immutable — no Add row, a distinct empty state.
    private var isBodyweightKit: Bool { activeLibrary?.isBodyweight ?? false }

    /// The active library's members, sorted for a stable list. (Narrowing
    /// by name moved to the universal Find-or-create surface, 2026-07-23.)
    private var libraryEquipment: [Equipment] {
        (activeLibrary?.members ?? []).sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // "Kit": the tab IS your active kit (2026-07-20). Short
                // enough to always fit the on-row heading next to the
                // switcher, whatever the kit is named. The header magnifier
                // retired into the universal Find-or-create surface
                // (2026-07-23).
                CatalogTabHeader(title: "Kit") {
                    LibrarySwitcherKey(name: activeLibrary?.name ?? EquipmentLibrary.defaultName) {
                        showingLibraryTray = true
                    }
                }

                ScrollViewReader { proxy in
                    List {
                        // Top row navigates to the catalog to add gear; New/Add
                        // never dead-ends an empty kit or a zeroed search. The
                        // null kit is immutable, so it shows no Add row.
                        if !isBodyweightKit {
                            addEquipmentRow
                        }
                        equipmentRows
                        if libraryEquipment.isEmpty {
                            equipmentEmptyHint
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                    // The arrival beat (the Exercises-tab twin): scroll the
                    // landed row into view, flash, clear. Cancellation bails
                    // without clearing.
                    .task(id: newlyAdded) {
                        guard let target = newlyAdded else { return }
                        do {
                            try await Task.sleep(for: .milliseconds(80))
                            withAnimation(Theme.Anim.standard) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                            try await Task.sleep(for: .seconds(2.2))
                            newlyAdded = nil
                        } catch {}
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Equipment.self) { equipment in
                EquipmentDetailScreen(equipment: equipment)
            }
            .sheet(isPresented: $showingLibraryTray) {
                EquipmentLibraryTray()
            }
        }
        .revealRoot(tab: "equipment", atRoot: path.isEmpty)
        // Gear membership changes / deletes reach GitHub when you leave the tab.
        // Cross-tab landing (the RoutineArrival shape): receive OR appear,
        // whichever fires first.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusEquipmentArrived)) { _ in
            consumeArrival()
        }
        .onAppear(perform: consumeArrival)
    }

    /// Land a cross-tab add: pop to the root, arm the scroll + flash.
    private func consumeArrival() {
        guard let pending = EquipmentArrival.pending else { return }
        EquipmentArrival.pending = nil
        path = NavigationPath()
        newlyAdded = pending
    }

    /// The Add row (Add family — it NAVIGATES): opens Find or create
    /// pre-scoped to Kit, where the catalog and creation are one surface
    /// (2026-07-23). Keeps the `addEquipmentRow` id.
    private var addEquipmentRow: some View {
        CreateRow(label: "Add equipment", identifier: "addEquipmentRow") {
            FindOrCreateLaunch.open(.kit)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    private var emptyHintText: String {
        // The null kit is empty on purpose — say so, and point to the switch.
        if isBodyweightKit {
            return "Switch to another kit to add equipment. null is the no-equipment kit."
        }
        // A fresh install seeds an empty kit (#232) — say what the list is for.
        return "Your kit is empty. Add equipment to unlock exercises and routines."
    }

    private var equipmentEmptyHint: some View {
        VStack(spacing: 10) {
            Text(emptyHintText)
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var equipmentRows: some View {
        ForEach(libraryEquipment) { equipment in
            SwipeRevealRow(
                id: equipment.persistentModelID,
                openRow: $openSwipeRow,
                actionsWidth: 58,
                onTap: { path.append(equipment) },
                accessibilityActions: [
                    SwipeRowAction(name: equipment.isBuiltIn ? "Remove" : "Delete") {
                        openSwipeRow = nil
                        remove(equipment)
                    }
                ]
            ) {
                // Same representation as the catalog card (2026-07-18);
                // the kit list omits the in-kit glyph (every row is in it).
                EquipmentRowContent(
                    equipment: equipment,
                    unlockedCount: unlockedCount(for: equipment),
                    inKit: nil
                )
            } actions: {
                SwipeActionButton(label: equipment.isBuiltIn ? "REMOVE" : "DELETE", color: Theme.destructive) {
                    openSwipeRow = nil
                    remove(equipment)
                }
            }
            .overlay {
                if newlyAdded == equipment.persistentModelID {
                    RowEntranceFlash()
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
        }
    }

    private func unlockedCount(for equipment: Equipment) -> Int {
        allExercises.filter { $0.equipment.contains(where: { $0 === equipment }) }.count
    }

    private func remove(_ equipment: Equipment) {
        if equipment.isBuiltIn {
            // "REMOVE" here is membership only: drop it from THIS library
            // (the gear stays in the catalog and your other libraries).
            activeLibrary?.setMembership(equipment, false)
        } else {
            // Belt-and-braces since #196 gave the relationship an
            // explicit inverse: stripping references first keeps
            // deletion order-independent (bug hunt B1).
            for exercise in allExercises {
                exercise.equipment.removeAll { $0 === equipment }
            }
            modelContext.delete(equipment)
        }
    }
}

/// Shared header for the two catalog tabs: the ++ key, title, and the
/// contextual + button. An optional `accessory` rides just left of the +
/// (the Equipment tab's library switcher).

extension CatalogTabHeader where Accessory == EmptyView {
    init(title: String, addIdentifier: String? = nil, addLabel: String? = nil, onAdd: (() -> Void)? = nil, search: HeaderSearchConfig? = nil) {
        self.init(title: title, addIdentifier: addIdentifier, addLabel: addLabel, onAdd: onAdd, search: search, accessory: { EmptyView() })
    }
}

/// The Equipment tab's library switcher: a labeled key showing the
/// active library name, opening the tray. Shows a chevron so it reads as
/// "there's more than this here" even with one library (the concept is


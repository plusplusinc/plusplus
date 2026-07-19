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
    @AppStorage(ExerciseFilterState.Prefs.gearMode) private var prefGearMode = ""
    @AppStorage(ExerciseFilterState.Prefs.pickedGear) private var prefPickedGear = "[]"
    @AppStorage(ExerciseFilterState.Prefs.muscleGroups) private var prefMuscleGroups = "[]"

    @State private var filterState = ExerciseFilterState()
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    @State private var path = NavigationPath()
    @State private var showingMuscleFilter = false
    @State private var showingGearPicker = false
    @State private var creatingExercise = false
    @State private var loadedPrefs = false

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    private var candidates: [Exercise] {
        filterState.filteredExercises(from: allExercises, kitNames: availableEquipmentNames)
    }

    private var anyFilterActive: Bool {
        filterState.favoritesOnly
            || filterState.gearMode != nil
            || !filterState.selectedMuscleGroups.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(
                    title: "Exercises",
                    // Creation moved into the list (a top create row), so the
                    // header's top-right is the expanding search (2026-07-18).
                    search: HeaderSearchConfig(
                        text: Bindable(filterState).searchText,
                        prompt: "Search exercises",
                        identifier: "exercisesSearchField"
                    )
                )
                filterRow
                List {
                    // Creation is the top row everywhere (2026-07-18): New
                    // exercise, or Create "<query>" when searching.
                    createExerciseRow
                    ForEach(candidates) { exercise in
                        exerciseRow(exercise)
                    }
                    if candidates.isEmpty {
                        emptyResults
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
            .sheet(isPresented: $creatingExercise) {
                ExerciseEditorView(
                    prefillName: filterState.prefillName,
                    prefillMuscleGroup: filterState.prefillMuscleGroup
                )
            }
            .sheet(isPresented: $showingMuscleFilter) {
                MuscleGroupFilterSheet(filterState: filterState)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingGearPicker) {
                GearPickSheet(filterState: filterState, allEquipment: allEquipmentSorted)
                    .presentationDetents([.medium, .large])
            }
        }
        .revealRoot(tab: "exercises", atRoot: path.isEmpty)
        // Favorites + custom deletes reach GitHub when you leave the tab.
        .syncsProgramOnClose()
        .onAppear {
            guard !loadedPrefs else { return }
            loadedPrefs = true
            loadPrefs()
        }
        // Mirror in-session filter changes back to storage.
        .onChange(of: filterState.favoritesOnly) { persistPrefs() }
        .onChange(of: filterState.gearMode) { persistPrefs() }
        .onChange(of: filterState.pickedGearNames) { persistPrefs() }
        .onChange(of: filterState.selectedMuscleGroups) { persistPrefs() }
    }

    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    private var allEquipmentSorted: [Equipment] { allEquipment }

    // MARK: - Create row + empty state

    /// The whole catalog is here, so an empty list is only ever a zeroed
    /// filter/search — the create row (always at the top) turns "not here"
    /// into "make it", and Clear filters is the escape. Never a dead end.
    private var createLabel: String {
        let q = filterState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "New exercise" : "Create \u{201C}\(q.sentenceCasedFirst)\u{201D}"
    }

    private var createExerciseRow: some View {
        CreateRow(label: createLabel, identifier: "createExerciseRow") {
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
                    filterState.gearMode = nil
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
                    ClearAllChip {
                        filterState.favoritesOnly = false
                        filterState.gearMode = nil
                        filterState.selectedMuscleGroups = []
                    }
                }
                SelectableChip(label: "Favorites", isSelected: filterState.favoritesOnly) {
                    filterState.favoritesOnly.toggle()
                }
                FacetChip(
                    facet: "Gear",
                    selection: gearBinding,
                    options: [
                        (ExerciseFilterState.GearMode.withKit, "Can do now"),
                        (.withoutKit, "Can't yet"),
                        (.handPicked, pickedGearLabel),
                    ]
                )
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

    private var pickedGearLabel: String {
        let n = filterState.pickedGearNames.count
        return n > 0 ? "Picked gear (\(n))" : "Picked gear"
    }

    /// Selecting "Picked gear" opens the picker AND lights the mode; the
    /// other modes commit directly. (The binding interceptor pattern from
    /// the equipment catalog's gear facet.)
    private var gearBinding: Binding<ExerciseFilterState.GearMode?> {
        Binding(
            get: { filterState.gearMode },
            set: { newValue in
                filterState.gearMode = newValue
                if newValue == .handPicked { showingGearPicker = true }
            }
        )
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
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
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
        filterState.gearMode = ExerciseFilterState.GearMode(rawValue: prefGearMode)
        filterState.pickedGearNames = decodeNames(prefPickedGear)
        filterState.selectedMuscleGroups = Set(
            decodeNames(prefMuscleGroups).compactMap(MuscleGroup.init(rawValue:))
        )
    }

    private func persistPrefs() {
        prefFavoritesOnly = filterState.favoritesOnly
        prefGearMode = filterState.gearMode?.rawValue ?? ""
        prefPickedGear = encodeNames(filterState.pickedGearNames)
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

/// The hand-picked gear set for the GEAR facet's "Picked gear" mode:
/// pick from ALL equipment (not just the active kit) — the point is to
/// ask "what could I do with X and Y", regardless of what's in the kit.
/// Writes `pickedGearNames` (names, so imports/reinstalls resolve).
struct GearPickSheet: View {
    @Environment(\.dismiss) private var dismiss
    var filterState: ExerciseFilterState
    let allEquipment: [Equipment]

    private var clearAction: (() -> Void)? {
        filterState.pickedGearNames.isEmpty ? nil : { filterState.pickedGearNames.removeAll() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "Picked gear",
                onCancel: clearAction,
                cancelLabel: "Clear",
                action: { dismiss() }
            )
            Text("Show exercises you could do with any of these, whatever's in your kit.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(allEquipment) { equipment in
                        SelectableChip(
                            label: equipment.name,
                            isSelected: filterState.pickedGearNames.contains(equipment.name)
                        ) {
                            if filterState.pickedGearNames.contains(equipment.name) {
                                filterState.pickedGearNames.remove(equipment.name)
                            } else {
                                filterState.pickedGearNames.insert(equipment.name)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
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

    @State private var showingCatalog = false
    @State private var showingLibraryTray = false
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    @State private var path = NavigationPath()
    /// Filters the kit list by name (2026-07-18); the add row threads it
    /// into the catalog's own search so "Add <query>" lands ready to add.
    @State private var searchText = ""
    @State private var pendingCatalogQuery = ""

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// The active library's members, sorted for a stable list.
    private var libraryEquipment: [Equipment] {
        (activeLibrary?.members ?? []).sorted { $0.name < $1.name }
    }

    /// Narrowed by the header search (forgiving, best-match-first), the
    /// same fuzzy match the catalogs use.
    private var filteredEquipment: [Equipment] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return libraryEquipment }
        return FuzzySearch.ranked(libraryEquipment, query: q) { $0.name }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(
                    title: "Equipment",
                    // Adding gear happens in the catalog, so the top row
                    // NAVIGATES there (Add family); the header's top-right
                    // is the expanding search over your kit (2026-07-18).
                    search: HeaderSearchConfig(
                        text: $searchText,
                        prompt: "Search your kit",
                        identifier: "equipmentKitSearchField"
                    )
                ) {
                    LibrarySwitcherKey(name: activeLibrary?.name ?? EquipmentLibrary.defaultName) {
                        showingLibraryTray = true
                    }
                }

                List {
                    // Top row navigates to the catalog to add gear; New/Add
                    // never dead-ends an empty kit or a zeroed search.
                    addEquipmentRow
                    equipmentRows
                    if filteredEquipment.isEmpty {
                        equipmentEmptyHint
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Equipment.self) { equipment in
                EquipmentDetailScreen(equipment: equipment)
            }
            .navigationDestination(isPresented: $showingCatalog) {
                EquipmentCatalogScreen(initialQuery: pendingCatalogQuery)
            }
            .sheet(isPresented: $showingLibraryTray) {
                EquipmentLibraryTray()
            }
        }
        .revealRoot(tab: "equipment", atRoot: path.isEmpty && !showingCatalog)
        // Gear membership changes / deletes reach GitHub when you leave the tab.
        .syncsProgramOnClose()
    }

    private var addLabel: String {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? "Add equipment" : "Add \u{201C}\(q.sentenceCasedFirst)\u{201D}"
    }

    private var addEquipmentRow: some View {
        CreateRow(label: addLabel, identifier: "addEquipmentRow") {
            pendingCatalogQuery = searchText.trimmingCharacters(in: .whitespaces)
            showingCatalog = true
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    private var equipmentEmptyHint: some View {
        VStack(spacing: 10) {
            // A fresh install seeds an empty kit (#232) — say what the list
            // is for; a zeroed search just says nothing matched.
            Text(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "Your kit is empty. Add equipment to unlock exercises and routines."
                 : "Nothing in your kit matches.")
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
        ForEach(filteredEquipment) { equipment in
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
struct CatalogTabHeader<Accessory: View>: View {
    let title: String
    // The tab's create action; optional so title-only headers work.
    // Explicit `= nil` so the accessory-form memberwise init can omit these
    // (both catalog tabs moved creation into a list row, 2026-07-18).
    var addIdentifier: String? = nil
    /// Spoken VoiceOver name for the add key; falls back to "Add <title>".
    var addLabel: String? = nil
    var onAdd: (() -> Void)? = nil
    /// Optional expanding search (2026-07-18): the magnifier rides the
    /// top-right of the icon row and expands into a field that spans the
    /// row (the big title hides while searching), the same affordance the
    /// pushed catalogs use — one search UI everywhere.
    var search: HeaderSearchConfig? = nil
    @ViewBuilder var accessory: () -> Accessory

    @State private var searchExpanded = false

    private var searching: Bool { search != nil && searchExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Every root header wears the ++ key (Dave, build 44); it
                // toggles the shared reveal drawer.
                AppMenuKey()
                if let search {
                    // `HeaderSearchField` is a SINGLE stable instance; its
                    // Spacer/accessory/add key are conditionalized around it
                    // so it keeps identity (and its one-shot focus intent)
                    // across expand/collapse — see PushedHeader's note.
                    if !searchExpanded {
                        Spacer(minLength: 0)
                        accessory()
                        if let onAdd {
                            HeaderIconButton(systemImage: "plus", accessibilityLabel: addLabel ?? "Add \(title)", identifier: addIdentifier) {
                                onAdd()
                            }
                        }
                    }
                    HeaderSearchField(config: search, isExpanded: $searchExpanded)
                } else {
                    Spacer(minLength: 0)
                    accessory()
                    if let onAdd {
                        HeaderIconButton(systemImage: "plus", accessibilityLabel: addLabel ?? "Add \(title)", identifier: addIdentifier) {
                            onAdd()
                        }
                    }
                }
            }
            if !searching {
                Text(title)
                    .font(.system(.title, weight: .bold))
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

extension CatalogTabHeader where Accessory == EmptyView {
    init(title: String, addIdentifier: String? = nil, addLabel: String? = nil, onAdd: (() -> Void)? = nil, search: HeaderSearchConfig? = nil) {
        self.init(title: title, addIdentifier: addIdentifier, addLabel: addLabel, onAdd: onAdd, search: search, accessory: { EmptyView() })
    }
}

/// The Equipment tab's library switcher: a labeled key showing the
/// active library name, opening the tray. Shows a chevron so it reads as
/// "there's more than this here" even with one library (the concept is
/// discoverable before a second library exists).
struct LibrarySwitcherKey: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityIdentifier("librarySwitcherButton")
    }
}


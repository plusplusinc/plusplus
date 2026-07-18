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
                    addIdentifier: "addExercisesButton",
                    addLabel: "Add exercise",
                    onAdd: { creatingExercise = true }
                )
                // Search + filters sit UNDER the header, pinned above the
                // scrolling list (Dave, 2026-07-18: a top `safeAreaInset`
                // floated them ABOVE the ++/title chrome — every other tab
                // root wears the ++ key topmost).
                VStack(spacing: 8) {
                    SearchField(prompt: "Search exercises", text: Bindable(filterState).searchText)
                        .padding(.horizontal, 16)
                    filterRow
                }
                List {
                    ForEach(candidates) { exercise in
                        exerciseRow(exercise)
                    }
                    if candidates.isEmpty {
                        Text("Nothing matches these filters.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
                    facet: "GEAR",
                    selection: gearBinding,
                    options: [
                        (ExerciseFilterState.GearMode.withKit, "Can do now"),
                        (.withoutKit, "Can't yet"),
                        (.handPicked, pickedGearLabel),
                    ]
                )
                TrayFilterChip(
                    facet: "MUSCLE",
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
            HStack(spacing: 10) {
                if exercise.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    subtitleText(for: exercise)
                        .font(.system(.caption))
                        .lineLimit(2)
                }
                Spacer()
                if !exercise.isBuiltIn {
                    Text("CUSTOM")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
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

    /// Muscle · gear, with the missing-gear gap flagged in notes amber
    /// (mock 03: "needs Bench" is attention, not chrome), relative to the
    /// active kit.
    private func subtitleText(for exercise: Exercise) -> Text {
        let equipment = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        var text = Text("\(exercise.muscleGroup.displayName) · \(equipment.isEmpty ? "Bodyweight" : equipment)")
            .foregroundStyle(Theme.textSecondary)
        let missing = ExerciseFilterState.missingEquipment(for: exercise, available: availableEquipmentNames)
        if !missing.isEmpty {
            text = text + Text(" · ").foregroundStyle(Theme.textSecondary)
                + Text("needs \(missing.joined(separator: ", "))").foregroundStyle(Theme.notes)
        }
        return text
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

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// The active library's members, sorted for a stable list.
    private var libraryEquipment: [Equipment] {
        (activeLibrary?.members ?? []).sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(
                    title: "Equipment",
                    addIdentifier: "addEquipmentButton",
                    addLabel: "Add equipment",
                    onAdd: { showingCatalog = true }
                ) {
                    LibrarySwitcherKey(name: activeLibrary?.name ?? EquipmentLibrary.defaultName) {
                        showingLibraryTray = true
                    }
                }

                if libraryEquipment.isEmpty {
                    LibraryEmptyState(
                        title: "No Equipment",
                        systemImage: "dumbbell",
                        message: "Pick what you have. Exercises and routines then match to the gear in this kit.",
                        ctaIdentifier: "emptyEquipmentCatalogButton"
                    ) { showingCatalog = true }
                } else {
                    List {
                        equipmentRows
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Equipment.self) { equipment in
                EquipmentDetailScreen(equipment: equipment)
            }
            .navigationDestination(isPresented: $showingCatalog) {
                EquipmentCatalogScreen()
            }
            .sheet(isPresented: $showingLibraryTray) {
                EquipmentLibraryTray()
            }
        }
        .revealRoot(tab: "equipment", atRoot: path.isEmpty && !showingCatalog)
        // Gear membership changes / deletes reach GitHub when you leave the tab.
        .syncsProgramOnClose()
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
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(equipment.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(equipmentSubtitle(for: equipment))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
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

    private func equipmentSubtitle(for equipment: Equipment) -> String {
        let used = allExercises.filter { $0.equipment.contains(where: { $0 === equipment }) }.count
        var text = used == 0 ? "unused" : (used == 1 ? "1 exercise" : "\(used) exercises")
        if !equipment.isBuiltIn { text += " · custom" }
        return text
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

/// Empty state for the two library tabs (#232): fresh installs seed
/// NOTHING into the library, so this is the first thing a new user
/// sees here — it explains what the list is for and points at the
/// catalog. The CTA is green: it leads to adding (#202).
struct LibraryEmptyState: View {
    let title: String
    let systemImage: String
    let message: String
    let ctaIdentifier: String
    let onBrowse: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button(action: onBrowse) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .semibold))
                    Text("Browse the catalog")
                        .font(.system(.footnote, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong)
                )
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier(ctaIdentifier)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Shared header for the two catalog tabs: the ++ key, title, and the
/// contextual + button. An optional `accessory` rides just left of the +
/// (the Equipment tab's library switcher).
struct CatalogTabHeader<Accessory: View>: View {
    let title: String
    // The tab's create action; optional so title-only headers work.
    var addIdentifier: String?
    /// Spoken VoiceOver name for the add key; falls back to "Add <title>".
    var addLabel: String? = nil
    var onAdd: (() -> Void)?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Every root header wears the ++ key (Dave, build 44); it
                // toggles the shared reveal drawer.
                AppMenuKey()
                Spacer(minLength: 0)
                accessory()
                if let onAdd {
                    HeaderIconButton(systemImage: "plus", accessibilityLabel: addLabel ?? "Add \(title)", identifier: addIdentifier) {
                        onAdd()
                    }
                }
            }
            Text(title)
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

extension CatalogTabHeader where Accessory == EmptyView {
    init(title: String, addIdentifier: String? = nil, addLabel: String? = nil, onAdd: (() -> Void)? = nil) {
        self.init(title: title, addIdentifier: addIdentifier, addLabel: addLabel, onAdd: onAdd, accessory: { EmptyView() })
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


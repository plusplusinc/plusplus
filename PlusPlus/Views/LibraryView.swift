import SwiftUI
import SwiftData
import PlusPlusKit

/// The personal catalog, v3 (#109): LibraryView split into two tabs —
/// Exercises and Equipment — curated lists with a contextual header +
/// (no search here, #233: search lives on the catalogs). Built-ins
/// removed here leave the library but stay in the catalog; customs
/// are edited or deleted here.
struct ExercisesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    @State private var showingCatalog = false
    @State private var openSwipeRow: PersistentIdentifier?
    @State private var path = NavigationPath()

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    private var libraryExercises: [Exercise] {
        allExercises.filter { $0.inLibrary || !$0.isBuiltIn }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // No search here (#233): the curated list is short by
                // definition; search lives on the catalogs. The + is
                // back in the header.
                CatalogTabHeader(
                    title: "Exercises",
                    addIdentifier: "addExercisesButton",
                    addLabel: "Add exercise",
                    onAdd: { showingCatalog = true }
                )

                if libraryExercises.isEmpty {
                    // Empty is the fresh-install default (#185/#232) —
                    // say what the library is FOR, then point at the
                    // catalog (same voice as the Routines empty state).
                    LibraryEmptyState(
                        title: "No Exercises",
                        systemImage: "list.bullet",
                        message: "Your library is the short list you actually do. Pick from the catalog — anything you use in a routine joins on its own.",
                        ctaIdentifier: "emptyExercisesCatalogButton"
                    ) { showingCatalog = true }
                } else {
                    List {
                        exerciseRows
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
            // Full-page push, not a tray (#139 follow-up): the catalog
            // browser is a browsing surface — search, filters, a long
            // toggle list. Sheets stay for create/edit forms only.
            // isPresented is safe here (unlike the routine catalog):
            // nothing appends to the path beneath these screens.
            .navigationDestination(isPresented: $showingCatalog) {
                CatalogBrowseScreen(kind: .exercises)
            }
        }
        // The catalog pushes via isPresented (not the path); include it so
        // swipe-to-open yields to its swipe-back.
        .revealRoot(tab: "exercises", atRoot: path.isEmpty && !showingCatalog)
    }

    // MARK: - Rows

    @ViewBuilder
    private var exerciseRows: some View {
        ForEach(libraryExercises) { exercise in
            // Custom reveal everywhere (Dave reversed the native call:
            // no mixed affordances). Activation is the component's
            // onTap — no Button in content (see the component contract).
            SwipeRevealRow(
                id: exercise.persistentModelID,
                openRow: $openSwipeRow,
                actionsWidth: 58,
                onTap: { path.append(exercise) },
                accessibilityActions: [
                    SwipeRowAction(name: exercise.isBuiltIn ? "Remove" : "Delete") {
                        openSwipeRow = nil
                        remove(exercise)
                    }
                ]
            ) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        subtitleText(for: exercise)
                            .font(.system(.caption))
                            .lineLimit(1)
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
                // Reveal-then-tap always; the label says what it does
                // (a custom's removal is a permanent DELETE).
                SwipeActionButton(label: exercise.isBuiltIn ? "REMOVE" : "DELETE", color: Theme.destructive) {
                    openSwipeRow = nil
                    remove(exercise)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
        }
    }

    /// Curated items are never hidden by availability (#113) — your
    /// library is yours — but the gap is flagged, in notes amber
    /// (mock 03: "needs Bench" is attention, not chrome). "Missing" is
    /// relative to the ACTIVE equipment library.
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

    private func remove(_ exercise: Exercise) {
        if exercise.isBuiltIn {
            exercise.inLibrary = false
        } else {
            modelContext.delete(exercise)
        }
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
    @State private var openSwipeRow: PersistentIdentifier?
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
                        message: "Pick what you have access to. Exercises and routines then match to the gear in this library.",
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
                CatalogBrowseScreen(kind: .equipment)
            }
            .sheet(isPresented: $showingLibraryTray) {
                EquipmentLibraryTray()
            }
        }
        .revealRoot(tab: "equipment", atRoot: path.isEmpty && !showingCatalog)
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
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .frame(height: 48)
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

// MARK: - Add from catalog

/// The catalog browser, rethought as a curation surface (#139): the
/// whole catalog stays listed, membership is a Toggle per row — nothing
/// vanishes when you flip one. A full pushed page, not a tray (Dave):
/// browsing surfaces push, sheets are for forms. For EQUIPMENT the
/// toggle is membership in the ACTIVE library, and customs list here too
/// (they belong to specific libraries now, so this is where you add one
/// to another). For EXERCISES the toggle is the personal exercise
/// library, and customs live in the library list, not here (#113).
struct CatalogBrowseScreen: View {
    enum Kind: String, Identifiable {
        case exercises
        case equipment

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    let kind: Kind

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    private var availableEquipmentNames: Set<String> {
        activeLibrary?.memberNames ?? []
    }

    @State private var filterState = ExerciseFilterState()
    /// 0 = All · 1 = In library · 2 = Not in library.
    @State private var libraryFilter = 0
    @State private var showingMuscleFilter = false
    @State private var showingEquipmentFilter = false
    /// Prefill for the custom-exercise editor sheet (create/edit forms
    /// are the one thing that stays modal here).
    @State private var customPrefill: String?
    /// Custom gear is just a name, so an empty-query create prompts for
    /// one here instead of silently doing nothing (#170).
    @State private var promptingEquipmentName = false
    @State private var newEquipmentName = ""

    /// §F: onboarding + the Settings re-run ride the REAL catalog with
    /// a pinned confirm bar — the limited tray (and the preset strip,
    /// #203) died.
    var setupMode = false
    /// Only Today's onboarding step offers population on Done (#204) —
    /// Settings/Library re-runs are curation, not setup.
    var offersPopulateOnDone = false
    /// Any toggle touch counts as engagement: plain back then still
    /// marks setup done (never trap the user in a step).
    @State private var touchedSetup = false

    private var query: String { filterState.searchText }

    /// LIBRARY chip binding over the legacy 0/1/2 segmented value:
    /// nil = All.
    private var membershipBinding: Binding<Int?> {
        Binding(
            get: { libraryFilter == 0 ? nil : libraryFilter },
            set: { libraryFilter = $0 ?? 0 }
        )
    }

    private var anyFilterActive: Bool {
        libraryFilter != 0
            || !filterState.selectedMuscleGroups.isEmpty
            || !filterState.selectedEquipment.isEmpty
    }

    private func clearAllFilters() {
        libraryFilter = 0
        filterState.selectedMuscleGroups = []
        filterState.selectedEquipment = []
    }

    var body: some View {
        VStack(spacing: 0) {
            // One row for all narrowing (#237): membership as a
            // single-select chip, muscle/equipment as tray chips with
            // count pills, leading ✕ to clear.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if anyFilterActive {
                        ClearAllChip { clearAllFilters() }
                    }
                    // One name for membership across both kinds: gear is
                    // "in library" (the active equipment library), same
                    // word as exercises — availability, not ownership.
                    FacetChip(
                        facet: "LIBRARY",
                        selection: membershipBinding,
                        options: [(1, "In library"), (2, "Not in library")]
                    )
                    if kind == .exercises {
                        TrayFilterChip(
                            facet: "MUSCLE",
                            count: filterState.selectedMuscleGroups.count
                        ) { showingMuscleFilter = true }
                        TrayFilterChip(
                            facet: "EQUIPMENT",
                            count: filterState.selectedEquipment.count
                        ) { showingEquipmentFilter = true }
                    }
                    Spacer(minLength: 0)
                }
                .animation(Theme.Anim.standard, value: anyFilterActive)
                .padding(.horizontal, 16)
            }
            .padding(.top, 6)

            Button {
                createCustom()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .semibold))
                    Text(createLabel).font(.system(.footnote, weight: .semibold))
                }
                // Creation is green (#202) — a future increment, same
                // voice as the catalog dead-end create rows; the key
                // anatomy says "this makes something happen" (Quiet
                // Arcade: in-list creation rows are secondary keys).
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong)
                )
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List {
                if kind == .exercises {
                    ForEach(candidateExercises) { exercise in
                        toggleRow(
                            name: exercise.name,
                            sub: exerciseSubtitleText(exercise),
                            isOn: Binding(
                                get: { exercise.inLibrary },
                                set: {
                                    exercise.inLibrary = $0
                                    touchedSetup = true
                                }
                            )
                        )
                    }
                } else {
                    ForEach(candidateEquipment) { equipment in
                        toggleRow(
                            name: equipment.name,
                            sub: Text(equipmentSubtitle(equipment)).foregroundStyle(Theme.textSecondary),
                            isOn: Binding(
                                get: { activeLibrary?.contains(equipment) ?? false },
                                set: {
                                    activeLibrary?.setMembership(equipment, $0)
                                    touchedSetup = true
                                }
                            )
                        )
                    }
                }
                if candidatesEmpty {
                    Text("Nothing matches these filters.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if kind == .exercises, !filterState.showUnavailable, hiddenByAvailability > 0 {
                    // The availability escape hatch as a quiet key (Quiet
                    // Arcade retired selection blue as a link color).
                    QuietKey(
                        label: "\(hiddenByAvailability) more need equipment you don't have — show",
                        identifier: "showUnavailableToggle"
                    ) {
                        filterState.showUnavailable = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .padding(.top, 2)
        }
        .background(Theme.background)
        // Custom key chrome (build-42 call): centered title, in-header
        // expanding search.
        .pushedScreenChrome(
            title: kind == .exercises ? "Exercise catalog" : "Equipment catalog",
            search: HeaderSearchConfig(
                text: Bindable(filterState).searchText,
                prompt: "Search the catalog",
                identifier: "catalogSearchField"
            ),
            onBack: { dismiss() }
        )
        .safeAreaInset(edge: .bottom) {
            if setupMode {
                Button {
                    touchedSetup = true
                    SetupState.markEquipmentDone()
                    // Population stays the user's call (#185), but the
                    // ask moved to Today (#204) — a popover here floated
                    // anchored to nothing while the screen was leaving.
                    if kind == .equipment && offersPopulateOnDone {
                        SetupState.requestPopulateOffer()
                    }
                    dismiss()
                } label: {
                    Text(availableNames.isEmpty ? "Done · bodyweight only" : "Done · \(availableNames.count) item\(availableNames.count == 1 ? "" : "s")")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
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
                if kind == .equipment && offersPopulateOnDone {
                    SetupState.requestPopulateOffer()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { customPrefill != nil },
            set: { if !$0 { customPrefill = nil } }
        )) {
            ExerciseEditorView(prefillName: customPrefill ?? "")
        }
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
        .sheet(isPresented: $showingEquipmentFilter) {
            EquipmentFilterSheet(filterState: filterState, allEquipment: activeLibrary?.members.sorted { $0.name < $1.name } ?? [])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Rows

    private func toggleRow(name: String, sub: Text, isOn: Binding<Bool>) -> some View {
        // Toggle wraps the whole label: the full row flips it. Under the
        // default (All) membership filter the row stays put on flip —
        // visible state, not a disappearing act (#139); under an explicit
        // In/Not-in-library filter it correctly leaves the filtered set.
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                sub
                    .font(.system(.caption))
                    .lineLimit(1)
            }
        }
        .tint(Theme.selected)
        .accessibilityIdentifier("toggle-\(name)")
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
    }

    // MARK: - Candidates

    private var candidatesEmpty: Bool {
        kind == .exercises ? candidateExercises.isEmpty : candidateEquipment.isEmpty
    }

    private func matchesLibraryFilter(_ inLibrary: Bool) -> Bool {
        switch libraryFilter {
        case 1: inLibrary
        case 2: !inLibrary
        default: true
        }
    }

    private var candidateExercises: [Exercise] {
        filterState.filteredExercises(from: allExercises.filter(\.isBuiltIn), available: availableEquipmentNames)
            .filter { matchesLibraryFilter($0.inLibrary) }
    }

    /// Built-ins AND customs: a custom belongs to specific libraries now,
    /// so the catalog is where you add it to another one. Membership is
    /// active-library membership.
    private var candidateEquipment: [Equipment] {
        allEquipment
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .filter { matchesLibraryFilter(activeLibrary?.contains($0) ?? false) }
    }

    // The §F preset strip died here (#203): three bulk buttons that
    // could silently overwrite a curated equipment set in one tap, and
    // they crammed the top. Search + per-row toggles are the tool; a
    // bulk affordance returns only if real setup friction demands one,
    // and additive-only when it does.

    private var availableNames: Set<String> {
        availableEquipmentNames
    }

    /// Exercises the availability filter is currently hiding (§H escape
    /// hatch) — matches every OTHER active filter first.
    private var hiddenByAvailability: Int {
        let shown = candidateExercises.count
        let all = filterState.filteredExercises(
            from: allExercises.filter(\.isBuiltIn),
            available: availableEquipmentNames,
            overridingShowUnavailable: true
        ).filter { matchesLibraryFilter($0.inLibrary) }.count
        return max(0, all - shown)
    }

    private var createLabel: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return "Create “\(trimmed)”" }
        return kind == .exercises ? "Create custom exercise…" : "Create custom equipment…"
    }

    /// The gear gap in notes amber (mock 03), same as the library rows.
    private func exerciseSubtitleText(_ exercise: Exercise) -> Text {
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

    private func equipmentSubtitle(_ equipment: Equipment) -> String {
        let used = allExercises.filter { exercise in
            exercise.equipment.contains { $0 === equipment }
        }.count
        return used == 0 ? "No catalog exercise uses it" : "\(used) exercise\(used == 1 ? "" : "s") in the catalog"
    }

    private func createCustom() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if kind == .equipment {
            // Custom gear is just a name; with an empty query, ask for
            // one — the row used to silently do nothing here (#170).
            guard !trimmed.isEmpty else {
                newEquipmentName = ""
                promptingEquipmentName = true
                return
            }
            createEquipment(named: trimmed)
        } else {
            customPrefill = trimmed
        }
    }

    /// Creating custom gear adds it to the active library and pops back
    /// to the tab, where the new item is now visible.
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
        dismiss()
    }
}

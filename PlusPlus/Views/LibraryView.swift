import SwiftUI
import SwiftData
import TipKit
import PlusPlusKit

/// The personal catalog, v3 (#109): LibraryView split into two tabs —
/// Exercises and Equipment — each with its own search and contextual
/// header +. Built-ins removed here leave the library but stay in the
/// catalog; customs are edited or deleted here.
struct ExercisesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var search = ""
    @State private var openSwipeRow: PersistentIdentifier?
    @State private var showingCatalog = false
    @State private var path = NavigationPath()

    private var libraryExercises: [Exercise] {
        allExercises
            .filter { $0.inLibrary || !$0.isBuiltIn }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(title: "Exercises")

                List {
                    exerciseRows
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                // Rows feather out under the glass instead of
                // hard-clipping at the dock (#216 rides along).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                // Search floats at the bottom, Messages-style (#214);
                // rows scroll under the glass.
                .safeAreaInset(edge: .bottom) {
                    SearchDock(prompt: "Search", text: $search, addIdentifier: "addExercisesButton") {
                        showingCatalog = true
                    }
                }
                .popoverTip(SwipeActionsTip())
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
            // Full-page push, not a tray (#139 follow-up): the catalog
            // browser is a browsing surface — search, filters, a long
            // toggle list. Sheets stay for create/edit forms only.
            .navigationDestination(isPresented: $showingCatalog) {
                CatalogBrowseScreen(kind: .exercises)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var exerciseRows: some View {
        ForEach(libraryExercises) { exercise in
            SwipeRevealRow(id: exercise.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
            Button {
                if openSwipeRow != nil {
                    openSwipeRow = nil
                } else {
                    path.append(exercise)
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(subtitle(for: exercise))
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textSecondary)
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
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            } actions: {
                SwipeActionButton(label: "REMOVE", color: Theme.destructive) {
                    SwipeActionsTip().invalidate(reason: .actionPerformed)
                    openSwipeRow = nil
                    remove(exercise)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
        }
    }

    private func subtitle(for exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        var subtitle = "\(exercise.muscleGroup.displayName) · \(equipment.isEmpty ? "Bodyweight" : equipment)"
        // Curated items are never hidden by ownership (#113) — your
        // library is yours — but the gap is flagged.
        let missing = ExerciseFilterState.missingEquipment(for: exercise)
        if !missing.isEmpty {
            subtitle += " · needs \(missing.joined(separator: ", "))"
        }
        return subtitle
    }

    private func remove(_ exercise: Exercise) {
        if exercise.isBuiltIn {
            exercise.inLibrary = false
        } else {
            modelContext.delete(exercise)
        }
    }
}

/// The Equipment tab (#109): what you own. Feeds exercise filtering;
/// the v3 onboarding preset picker (#113) writes this same list.
struct EquipmentTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    @State private var search = ""
    @State private var openSwipeRow: PersistentIdentifier?
    @State private var showingCatalog = false
    @State private var path = NavigationPath()

    private var libraryEquipment: [Equipment] {
        allEquipment
            .filter { $0.inLibrary || !$0.isBuiltIn }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(title: "Equipment")

                List {
                    equipmentRows
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                // Rows feather out under the glass instead of
                // hard-clipping at the dock (#216 rides along).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .safeAreaInset(edge: .bottom) {
                    SearchDock(prompt: "Search", text: $search, addIdentifier: "addEquipmentButton") {
                        showingCatalog = true
                    }
                }
                .popoverTip(SwipeActionsTip())
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Equipment.self) { equipment in
                EquipmentDetailScreen(equipment: equipment)
            }
            .navigationDestination(isPresented: $showingCatalog) {
                CatalogBrowseScreen(kind: .equipment)
            }
        }
    }

    @ViewBuilder
    private var equipmentRows: some View {
        ForEach(libraryEquipment) { equipment in
            SwipeRevealRow(id: equipment.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
            Button {
                if openSwipeRow != nil {
                    openSwipeRow = nil
                } else {
                    path.append(equipment)
                }
            } label: {
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
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            } actions: {
                SwipeActionButton(label: "REMOVE", color: Theme.destructive) {
                    SwipeActionsTip().invalidate(reason: .actionPerformed)
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
            equipment.inLibrary = false
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

/// Shared header for the two catalog tabs: ++ glyph, title, and the
/// contextual + button.
struct CatalogTabHeader: View {
    let title: String
    // Creation moved into the SearchDock's glass circle (#214); the
    // slot stays for headers that still need a trailing action.
    var addIdentifier: String?
    var onAdd: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HeaderGlyph()
                Spacer()
                if let onAdd {
                    HeaderIconButton(systemImage: "plus", identifier: addIdentifier, tint: Theme.accent) {
                        onAdd()
                    }
                }
            }
            // The button slot is 44 pt on the other tabs' headers —
            // hold the height with it empty so tab-switching doesn't
            // bounce the title row.
            .frame(minHeight: 44)
            Text(title)
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Add from catalog

/// The catalog browser, rethought as a curation surface (#139): the
/// whole built-in catalog stays listed, membership is a Toggle per row
/// — nothing vanishes when you flip one. A full pushed page, not a
/// tray (Dave): browsing surfaces push, sheets are for forms. Filters:
/// library state (All / In library / Not in library), and for
/// exercises the picker's muscle-group/equipment sheets plus the
/// ownership escape hatch. Customs don't appear here — they live in
/// the library list, where deletion is a deliberate act, not a toggle.
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

    let kind: Kind

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

    var body: some View {
        VStack(spacing: 0) {
            CatalogDetailHeader(title: kind == .exercises ? "Exercise catalog" : "Equipment catalog") {
                EmptyView()
            }

            SearchField(prompt: "Search the catalog", text: Bindable(filterState).searchText)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            SegmentedTabs(options: ["All", "In library", "Not in library"], selectedIndex: $libraryFilter)
                .popoverTip(CatalogCurationTip())
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if kind == .exercises {
                HStack(spacing: 7) {
                    FilterDropdownButton(
                        label: "Muscle group",
                        selections: filterState.selectedMuscleGroups.sorted { $0.rawValue < $1.rawValue }.map(\.displayName),
                        action: { showingMuscleFilter = true }
                    )
                    FilterDropdownButton(
                        label: "Equipment",
                        selections: filterState.selectedEquipment.sorted { $0.name < $1.name }.map(\.name),
                        action: { showingEquipmentFilter = true }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

            }

            Button {
                createCustom()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .semibold))
                    Text(createLabel).font(.system(.footnote, weight: .semibold))
                }
                // Creation is green (#202) — a future increment, same
                // voice as the catalog dead-end create rows.
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List {
                if kind == .exercises {
                    ForEach(candidateExercises) { exercise in
                        toggleRow(
                            name: exercise.name,
                            sub: exerciseSubtitle(exercise),
                            isOn: Binding(
                                get: { exercise.inLibrary },
                                set: {
                                    exercise.inLibrary = $0
                                    touchedSetup = true
                                    CatalogCurationTip().invalidate(reason: .actionPerformed)
                                }
                            )
                        )
                    }
                } else {
                    ForEach(candidateEquipment) { equipment in
                        toggleRow(
                            name: equipment.name,
                            sub: equipmentSubtitle(equipment),
                            isOn: Binding(
                                get: { equipment.inLibrary },
                                set: {
                                    equipment.inLibrary = $0
                                    touchedSetup = true
                                    CatalogCurationTip().invalidate(reason: .actionPerformed)
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
                if kind == .exercises, !filterState.showUnowned, hiddenByOwnership > 0 {
                    Button {
                        filterState.showUnowned = true
                    } label: {
                        Text("\(hiddenByOwnership) more need equipment you don't have — show")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.selected)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("showUnownedToggle")
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
        .pushedScreenChrome(onBack: { dismiss() })
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
                    Text(ownedNames.isEmpty ? "Done — bodyweight only" : "Done — \(ownedNames.count) item\(ownedNames.count == 1 ? "" : "s")")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
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
            EquipmentFilterSheet(filterState: filterState, allEquipment: allEquipment.filter { $0.inLibrary || !$0.isBuiltIn })
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Rows

    private func toggleRow(name: String, sub: String, isOn: Binding<Bool>) -> some View {
        // Toggle wraps the whole label: the full row flips it, and the
        // row stays put either way — membership is visible state, not a
        // disappearing act (#139).
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
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
        filterState.filteredExercises(from: allExercises.filter(\.isBuiltIn))
            .filter { matchesLibraryFilter($0.inLibrary) }
    }

    private var candidateEquipment: [Equipment] {
        allEquipment
            .filter(\.isBuiltIn)
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .filter { matchesLibraryFilter($0.inLibrary) }
    }

    // The §F preset strip died here (#203): three bulk buttons that
    // could silently overwrite a curated equipment set in one tap, and
    // they crammed the top. Search + per-row toggles are the tool; a
    // bulk affordance returns only if real setup friction demands one,
    // and additive-only when it does.

    private var ownedNames: Set<String> {
        Set(allEquipment.filter { $0.isBuiltIn && $0.inLibrary }.map(\.name))
    }

    /// Exercises the ownership filter is currently hiding (§H escape
    /// hatch) — matches every OTHER active filter first.
    private var hiddenByOwnership: Int {
        let shown = candidateExercises.count
        let all = filterState.filteredExercises(
            from: allExercises.filter(\.isBuiltIn),
            overridingShowUnowned: true
        ).filter { matchesLibraryFilter($0.inLibrary) }.count
        return max(0, all - shown)
    }

    private var createLabel: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return "Create “\(trimmed)”" }
        return kind == .exercises ? "Create custom exercise…" : "Create custom equipment…"
    }

    private func exerciseSubtitle(_ exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        var subtitle = "\(exercise.muscleGroup.displayName) · \(equipment.isEmpty ? "Bodyweight" : equipment)"
        let missing = ExerciseFilterState.missingEquipment(for: exercise)
        if !missing.isEmpty {
            subtitle += " · needs \(missing.joined(separator: ", "))"
        }
        return subtitle
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

    /// Creating custom gear pops back to the library, where the new
    /// item is actually visible (customs aren't catalog rows).
    private func createEquipment(named name: String) {
        let existing = allEquipment.first { $0.name.lowercased() == name.lowercased() }
        if let existing {
            existing.inLibrary = true
        } else {
            modelContext.insert(Equipment(name: name, isBuiltIn: false))
        }
        dismiss()
    }
}

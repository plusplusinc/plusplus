import SwiftUI
import SwiftData
import TipKit
import PlusPlusKit

/// The personal catalog, v3 (#109): LibraryView split into two tabs —
/// Exercises and Equipment — curated lists with a contextual header +
/// (no search here, #233: search lives on the catalogs). Built-ins
/// removed here leave the library but stay in the catalog; customs
/// are edited or deleted here.
struct ExercisesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var showingCatalog = false
    @State private var openSwipeRow: PersistentIdentifier?
    @State private var path = NavigationPath()

    private var libraryExercises: [Exercise] {
        allExercises.filter { $0.inLibrary || !$0.isBuiltIn }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // No search here (#233): the curated list is short by
                // definition; search lives on the catalogs. The + is
                // back in the header.
                CatalogTabHeader(title: "Exercises", addIdentifier: "addExercisesButton") {
                    showingCatalog = true
                }

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
            .navigationDestination(isPresented: $showingCatalog) {
                CatalogBrowseScreen(kind: .exercises)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var exerciseRows: some View {
        ForEach(libraryExercises) { exercise in
            // Custom reveal everywhere (Dave reversed the native call:
            // no mixed affordances) — the snap-back is fixed in the
            // component (momentum floor + live commit).
            SwipeRevealRow(id: exercise.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
            Button {
                if openSwipeRow != nil { openSwipeRow = nil } else { path.append(exercise) }
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
            // Tap-triggered, NOT .plain: a plain Button fires on the
            // finger-lift ending a reveal drag and the tap-close branch
            // shut the row the drag just opened (build 33).
            .buttonStyle(TapTriggerButtonStyle())
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

    @State private var showingCatalog = false
    @State private var openSwipeRow: PersistentIdentifier?
    @State private var path = NavigationPath()

    private var libraryEquipment: [Equipment] {
        allEquipment.filter { $0.inLibrary || !$0.isBuiltIn }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CatalogTabHeader(title: "Equipment", addIdentifier: "addEquipmentButton") {
                    showingCatalog = true
                }

                if libraryEquipment.isEmpty {
                    LibraryEmptyState(
                        title: "No Equipment",
                        systemImage: "dumbbell",
                        message: "Pick what you own — exercises and routines can then be matched to gear you actually have.",
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
        }
    }

    @ViewBuilder
    private var equipmentRows: some View {
        ForEach(libraryEquipment) { equipment in
            SwipeRevealRow(id: equipment.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
            Button {
                if openSwipeRow != nil { openSwipeRow = nil } else { path.append(equipment) }
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
            // Tap-triggered, NOT .plain — see the exercise row above.
            .buttonStyle(TapTriggerButtonStyle())
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
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(ctaIdentifier)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Shared header for the two catalog tabs: ++ glyph, title, and the
/// contextual + button.
struct CatalogTabHeader: View {
    let title: String
    // The tab's create action; optional so title-only headers work.
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
                    // Equipment membership is OWNERSHIP — half the UI
                    // said "library" for it (FTUE audit): one concept,
                    // one name per kind.
                    FacetChip(
                        facet: kind == .equipment ? "OWNED" : "LIBRARY",
                        selection: membershipBinding,
                        options: kind == .equipment
                            ? [(1, "Owned"), (2, "Not owned")]
                            : [(1, "In library"), (2, "Not in library")]
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
                .animation(.easeOut(duration: 0.15), value: anyFilterActive)
                .padding(.horizontal, 16)
            }
            // Not in setup (FTUE audit): the tip's library-curation
            // copy contradicts the step's ownership framing, and it
            // pops at the flow's highest-anxiety moment. popoverTip
            // takes a concrete Tip, so the gate is structural.
            .modifier(CurationTipUnlessSetup(setupMode: setupMode))
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
                // voice as the catalog dead-end create rows.
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 48)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong)
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
        // Drilled-in pages carry inline titles (#234) — smaller than
        // roots, centered with the back chevron.
        .navigationTitle(kind == .exercises ? "Exercise catalog" : "Equipment catalog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExpandingSearchButton(prompt: "Search the catalog", text: Bindable(filterState).searchText, identifier: "catalogSearchField")
            }
        }
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

/// Structural gate for the curation tip: `popoverTip` takes `some Tip`
/// (no Optional), so setup mode branches around it entirely.
private struct CurationTipUnlessSetup: ViewModifier {
    let setupMode: Bool

    func body(content: Content) -> some View {
        if setupMode {
            content
        } else {
            content.popoverTip(CatalogCurationTip())
        }
    }
}

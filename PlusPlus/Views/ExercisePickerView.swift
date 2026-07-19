import SwiftUI
import SwiftData
import PlusPlusKit

// MARK: - Main View

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    var filterState: ExerciseFilterState
    /// Routine building PUSHES the picker onto its NavigationStack (clean
    /// pushed-catalog chrome); session adds present it as a sheet. Default
    /// sheet so the session call sites are unchanged.
    var pushed = false
    /// The configured-selection path (session adds): a row tap opens a
    /// configure sheet — set count + targets — stacked on the picker,
    /// and Add hands back the finished `SessionExerciseConfig`. When set,
    /// it takes precedence over `onSelect`.
    var onConfigured: ((SessionExerciseConfig) -> Void)?
    /// The plain path (routine building): a row tap selects immediately;
    /// the routine's own detail sheet does the configuring.
    var onSelect: ((Exercise) -> Void)?

    /// The configure sheet's working config (configured path only) —
    /// held so the sheet's edits survive to Add.
    @State private var pendingConfig: SessionExerciseConfig?

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    @State private var showingMuscleGroupFilter = false
    @State private var showingEquipmentFilter = false
    @State private var showingCreateSheet = false
    @State private var editingExercise: Exercise?
    @State private var deletionCandidate: Exercise?
    /// The picker now wears the app's custom chrome (2026-07-18): a text
    /// Cancel key + the expanding search, no system toolbar.
    @State private var searchExpanded = false

    /// The whole catalog (2026-07-17), favorites first so what you reach
    /// for surfaces when building a routine. Never availability-hides —
    /// missing gear is flagged on the row, not hidden.
    private var candidates: [Exercise] {
        let base = filterState.filteredExercises(from: allExercises, kitNames: availableEquipmentNames)
        // Stable favorites-first partition (Swift's sort isn't stable).
        return base.filter(\.isFavorite) + base.filter { !$0.isFavorite }
    }

    private var anyNarrowingActive: Bool {
        !filterState.searchText.isEmpty
            || !filterState.selectedMuscleGroups.isEmpty
            || !filterState.selectedEquipment.isEmpty
            || filterState.favoritesOnly
    }

    var body: some View {
        if pushed {
            // Routine building PUSHES the picker (Dave, 2026-07-19): it reads
            // as a drill-down and reuses the pushed catalogs' clean chrome
            // (back + centered title + expanding search) instead of a sheet's
            // custom top. Same List, same modals.
            VStack(spacing: 0) {
                filterBar
                pickerList
            }
            .background(Theme.background)
            .pushedScreenChrome(
                title: "Add exercise",
                search: searchConfig,
                onBack: { dismiss() }
            )
        } else {
            // Session adds stay a modal sheet (mid-workout / session overview):
            // a text Cancel where a pushed screen has its back key.
            NavigationStack {
                pickerList
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        // OPAQUE background (not a translucent `.bar` band) so
                        // the header + filters sit seamlessly on the sheet.
                        VStack(spacing: 10) {
                            pickerHeader
                            filterBar
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        .background(Theme.background)
                    }
            }
        }
    }

    private var filterBar: some View {
        FilterBar(
            filterState: filterState,
            showingMuscleGroupFilter: $showingMuscleGroupFilter,
            showingEquipmentFilter: $showingEquipmentFilter
        )
    }

    /// The shared list + its modals, presented either pushed or as a sheet.
    private var pickerList: some View {
        List {
            // Creation is the top row (2026-07-18): New exercise, or
            // Create "<query>" when searching — never a dead end.
            createExerciseRow
            ForEach(candidates) { exercise in
                Button {
                    if onConfigured != nil {
                        // Stack the configure sheet on the picker —
                        // no dismiss-then-present handoff (the
                        // documented presentation-drop class).
                        pendingConfig = SessionExerciseConfig(exercise: exercise)
                    } else {
                        onSelect?(exercise)
                        dismiss()
                    }
                } label: {
                    ExerciseRow(exercise: exercise, available: availableEquipmentNames)
                }
                .tint(.primary)
                .contextMenu {
                    if !exercise.isBuiltIn {
                        Button("Edit", systemImage: "pencil") {
                            editingExercise = exercise
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deletionCandidate = exercise
                        }
                    }
                }
            }
            if candidates.isEmpty {
                emptyResults
            }
        }
        // Plain list on the warm background, matching the Library
        // (the sibling exercise list). The default grouped style's
        // generous top inset was the oversized gap under the filter
        // row; plain seats the first exercise right below it.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .scrollDismissesKeyboard(.immediately)
        .sheet(isPresented: $showingCreateSheet) {
            // Whatever narrowed the picker seeds the new exercise
            // (the searched-for name, the filtered muscle/gear) —
            // the create path from a zeroed search starts from
            // what was being looked for, not from scratch.
            ExerciseEditorView(
                prefillName: filterState.prefillName,
                prefillMuscleGroup: filterState.prefillMuscleGroup,
                prefillEquipment: filterState.prefillEquipment,
                onCreated: createdRouter
            )
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditorView(editing: exercise)
        }
        // Configure-before-add (session picks): the sheet stacks on
        // the picker; Add commits the config and dismisses the picker
        // (iOS tears the stacked sheet down with its parent).
        .sheet(item: $pendingConfig) { config in
            ExerciseConfigSheet(config: config) {
                onConfigured?(config)
                dismiss()
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Exercise", role: .destructive) {
                if let exercise = deletionCandidate {
                    deleteExercise(exercise)
                }
                deletionCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deletionCandidate = nil
            }
        }
        .sheet(isPresented: $showingMuscleGroupFilter) {
            MuscleGroupFilterSheet(filterState: filterState)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingEquipmentFilter) {
            // No ownership toggle here: the picker never
            // ownership-hides (see the list comment above), so the
            // escape hatch would be a dead switch.
            EquipmentFilterSheet(
                filterState: filterState,
                allEquipment: EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.members.sorted { $0.name < $1.name } ?? []
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header + create + empty

    /// Routine build (select path): a freshly created custom exercise goes
    /// STRAIGHT into the routine and pops back, skipping the return to the
    /// picker. Session adds (onConfigured) keep the return-to-picker — a new
    /// exercise there configures next, so nil disables the shortcut.
    private var createdRouter: ((Exercise) -> Void)? {
        guard onConfigured == nil else { return nil }
        return { exercise in
            onSelect?(exercise)
            // Pop on the NEXT main-actor turn, after the editor sheet's own
            // dismissal has committed — popping this pushed picker in the SAME
            // turn the editor dismisses coalesces two teardowns and can drop
            // the pop, stranding the user on the picker (swift-reviewer catch).
            Task { @MainActor in dismiss() }
        }
    }

    private var searchConfig: HeaderSearchConfig {
        HeaderSearchConfig(
            text: Bindable(filterState).searchText,
            prompt: "Search exercises",
            identifier: "exercisePickerSearchField"
        )
    }

    private var pickerHeader: some View {
        // Mirrors the pushed catalogs' chrome (centered title flanked by keys)
        // so the picker reads as one of the catalog family — just with a text
        // "Cancel" where a pushed screen has its back key.
        ZStack {
            if !searchExpanded {
                Text("Add exercise")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 90)
            }
            HStack(spacing: 10) {
                // Dismiss is a word, never a ✕ (✕ collapses search) — §9.
                SheetDismissKey(label: "Cancel") { dismiss() }
                // Single stable `HeaderSearchField`; only the Spacer is
                // conditionalized around it, so it keeps its focus intent
                // across expand/collapse (see PushedHeader's note).
                if !searchExpanded { Spacer(minLength: 0) }
                HeaderSearchField(config: searchConfig, isExpanded: $searchExpanded)
            }
        }
        .padding(.horizontal, 16)
    }

    private var createLabel: String {
        let q = filterState.searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? "New exercise" : "Create \u{201C}\(q.sentenceCasedFirst)\u{201D}"
    }

    /// The whole catalog is here, so an empty list is only ever a zeroed
    /// filter/search — the create row (id `newExerciseButton`, kept for the
    /// smoke flows) turns "not here" into "make it", Clear filters is the
    /// escape. Never a dead end.
    private var createExerciseRow: some View {
        CreateRow(label: createLabel, identifier: "newExerciseButton") {
            showingCreateSheet = true
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    private var emptyResults: some View {
        let facetsActive = !filterState.selectedMuscleGroups.isEmpty
            || !filterState.selectedEquipment.isEmpty
            || filterState.favoritesOnly
        return VStack(spacing: 10) {
            Text("Nothing matches.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
            if facetsActive {
                QuietKey(label: "Clear filters", identifier: "clearPickerFilters") {
                    filterState.selectedMuscleGroups = []
                    filterState.selectedEquipment = []
                    filterState.favoritesOnly = false
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .listRowSeparator(.hidden)
    }

    private var deletionTitle: String {
        guard let exercise = deletionCandidate else { return "" }
        let uses = usageCount(of: exercise)
        if uses == 0 {
            return "Delete “\(exercise.name)”?"
        }
        return "Delete “\(exercise.name)”? It appears in \(uses) routine \(uses == 1 ? "entry" : "entries"), which will show as Unknown."
    }

    private func usageCount(of exercise: Exercise) -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<RoutineExercise>())) ?? []
        return all.filter { $0.exercise === exercise }.count
    }

    private func deleteExercise(_ exercise: Exercise) {
        modelContext.delete(exercise)
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {
    let exercise: Exercise
    let available: Set<String>

    var body: some View {
        // The picker shares the catalog's row body (2026-07-18) so an
        // exercise reads the same wherever it appears; no chevron here —
        // a tap selects, it doesn't push to detail.
        ExerciseRowContent(exercise: exercise, available: available, showsChevron: false)
    }
}

// MARK: - Filter Bar

private struct FilterBar: View {
    var filterState: ExerciseFilterState
    @Binding var showingMuscleGroupFilter: Bool
    @Binding var showingEquipmentFilter: Bool

    private var anyFilterActive: Bool {
        !filterState.selectedMuscleGroups.isEmpty
            || !filterState.selectedEquipment.isEmpty
            || filterState.favoritesOnly
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if anyFilterActive {
                    ClearAllChip {
                        filterState.selectedMuscleGroups = []
                        filterState.selectedEquipment = []
                        filterState.favoritesOnly = false
                    }
                }
                SelectableChip(label: "Favorites", isSelected: filterState.favoritesOnly) {
                    filterState.favoritesOnly.toggle()
                }
                TrayFilterChip(
                    facet: "Muscle",
                    count: filterState.selectedMuscleGroups.count
                ) { showingMuscleGroupFilter = true }
                TrayFilterChip(
                    facet: "Equipment",
                    count: filterState.selectedEquipment.count
                ) { showingEquipmentFilter = true }
                Spacer(minLength: 0)
            }
            .animation(Theme.Anim.standard, value: anyFilterActive)
            .padding(.horizontal)
        }
        // The seal (the .bar background) now lives on the whole sticky
        // header in the safeAreaInset above, so the search-to-filter band
        // is covered too; this bar just carries its own vertical rhythm.
        .padding(.vertical, 8)
    }
}


// MARK: - Muscle Group Filter Sheet

/// Internal (not private): the catalog tray (#139) reuses it.
struct MuscleGroupFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    var filterState: ExerciseFilterState

    /// Clear appears only while a selection exists (v4 §C table).
    private var clearAction: (() -> Void)? {
        filterState.selectedMuscleGroups.isEmpty
            ? nil
            : { filterState.selectedMuscleGroups.removeAll() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "Muscle group",
                onCancel: clearAction,
                cancelLabel: "Clear",
                action: { dismiss() }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(MuscleGroup.grouped, id: \.region) { region, groups in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(region)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            FlowLayout(spacing: 8) {
                                ForEach(groups) { muscleGroup in
                                    SelectableChip(
                                        label: muscleGroup.displayName,
                                        isSelected: filterState.selectedMuscleGroups.contains(muscleGroup)
                                    ) {
                                        filterState.selectedMuscleGroups.toggle(muscleGroup)
                                    }
                                }
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

// MARK: - Equipment Filter Sheet

/// Internal (not private): the catalog tray (#139) reuses it.
struct EquipmentFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    var filterState: ExerciseFilterState
    let allEquipment: [Equipment]

    @State private var showingEquipmentEditor = false

    /// Clear appears only while a selection exists (v4 §C table).
    private var clearAction: (() -> Void)? {
        filterState.selectedEquipment.isEmpty
            ? nil
            : { filterState.selectedEquipment.removeAll() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "Equipment",
                onCancel: clearAction,
                cancelLabel: "Clear",
                action: { dismiss() }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if allEquipment.isEmpty {
                        // An empty active library is the fresh-install
                        // default (#232) — say why the tray is empty
                        // instead of rendering a bare toggle under nothing.
                        Text("This filters by the gear in your kit. Add what you have on the Equipment tab and it shows up here.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, 14)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(allEquipment) { equipment in
                                SelectableChip(
                                    label: equipment.name,
                                    isSelected: filterState.selectedEquipment.contains(equipment)
                                ) {
                                    filterState.selectedEquipment.toggle(equipment)
                                }
                            }
                        }
                        .padding(.vertical)
                    }

                    // Fix the filter's basis in place (#260): the
                    // options above ARE your equipment — edit it here
                    // instead of backing out to the Equipment tab.
                    QuietKey(label: "Edit my equipment…", identifier: "editEquipmentFromFilter") {
                        showingEquipmentEditor = true
                    }
                    .padding(.top, 8)
                }
            }
            .sheet(isPresented: $showingEquipmentEditor) {
                NavigationStack {
                    EquipmentCatalogScreen()
                }
            }
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
    }
}

// MARK: - Set Toggle Helper

private extension Set {
    mutating func toggle(_ member: Element) {
        if contains(member) {
            remove(member)
        } else {
            insert(member)
        }
    }
}

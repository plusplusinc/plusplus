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
    @State private var showingCatalog = false
    @State private var editingExercise: Exercise?
    @State private var deletionCandidate: Exercise?

    /// Every row here is a library/custom row, and curated rows are
    /// never hidden, only flagged (#113) — so the ownership hide does
    /// NOT apply in the picker. Before #232 this was dormant (fresh
    /// stores owned everything); with opt-in ownership it would have
    /// hidden the user's own exercises behind gear they hadn't picked
    /// yet (swift-reviewer catch on the #232 diff).
    private var candidates: [Exercise] {
        filterState.filteredExercises(
            from: allExercises.filter { $0.inLibrary || !$0.isBuiltIn },
            available: availableEquipmentNames,
            overridingShowUnavailable: true
        )
    }

    private var libraryCount: Int {
        allExercises.count { $0.inLibrary || !$0.isBuiltIn }
    }

    private var anyNarrowingActive: Bool {
        !filterState.searchText.isEmpty
            || !filterState.selectedMuscleGroups.isEmpty
            || !filterState.selectedEquipment.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                // Post-#232 an empty library is the fresh-install
                // default, and this sheet was its dead end (#246 —
                // both audits' top finding): say where exercises come
                // from instead of rendering a blank list whose only
                // action authors a custom from scratch.
                if candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        // "Empty" only when it truly is — filters and
                        // search zeroing the list get their own words
                        // (swift-reviewer catch: a muscle chip could
                        // make a 150-exercise library claim emptiness).
                        Text(anyNarrowingActive ? "Nothing in your library matches" : "Your library is empty")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Pick from the catalog — anything you use joins your library on its own.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                }
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
                // The catalog escape (#246): persistent while the
                // LIBRARY is thin (unfiltered — the contract is about
                // the library, not the current search), and on any
                // zero state (a searched-for exercise may live in the
                // catalog un-added). The picker's library contract
                // holds: catalog rows never mix in.
                if libraryCount < 5 || candidates.isEmpty {
                    Button {
                        showingCatalog = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(.caption, weight: .semibold))
                            Text("From the catalog…")
                                .font(.system(.footnote, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        // Creation is green (#202).
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius)
                                .strokeBorder(Theme.borderStrong)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pickerCatalogButton")
                    .listRowSeparator(.hidden)
                }
            }
            // Plain list on the warm background, matching the Library
            // (the sibling exercise list). The default grouped style's
            // generous top inset was the oversized gap under the filter
            // row; plain seats the first exercise right below it.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Exercise", systemImage: "plus") {
                        showingCreateSheet = true
                    }
                    // Creation is green (#202).
                    .tint(Theme.accent)
                    .accessibilityIdentifier("newExerciseButton")
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                // Whatever narrowed the picker seeds the new exercise
                // (the searched-for name, the filtered muscle/gear) —
                // the create path from a zeroed search starts from
                // what was being looked for, not from scratch.
                ExerciseEditorView(
                    prefillName: filterState.prefillName,
                    prefillMuscleGroup: filterState.prefillMuscleGroup,
                    prefillEquipment: filterState.prefillEquipment
                )
            }
            // The catalog browser is a pushed page by design; inside
            // this sheet it gets its own stack. Toggling membership
            // there updates the @Query-driven list live on return.
            .sheet(isPresented: $showingCatalog) {
                NavigationStack {
                    CatalogBrowseScreen(kind: .exercises)
                }
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
            .safeAreaInset(edge: .top, spacing: 0) {
                // One continuous bar behind search AND filters: the two
                // used to carry separate backgrounds, leaving a transparent
                // band between them that let scrolled-up rows peek through.
                VStack(spacing: 8) {
                    SearchField(prompt: "Search exercises", text: Bindable(filterState).searchText)
                        .padding(.horizontal, 16)
                    FilterBar(
                        filterState: filterState,
                        showingMuscleGroupFilter: $showingMuscleGroupFilter,
                        showingEquipmentFilter: $showingEquipmentFilter
                    )
                }
                .padding(.top, 8)
                .background(.bar)
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
                    allEquipment: EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.members.sorted { $0.name < $1.name } ?? [],
                    showsAvailabilityToggle: false
                )
                .presentationDetents([.medium, .large])
            }
        }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            // The flag half of #113's "flagged, never hidden": library
            // rows always list; this line carries the gear gap relative
            // to the active library.
            if !missing.isEmpty {
                Text("needs \(missing.joined(separator: ", "))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.notes)
            }
        }
    }

    private var missing: [String] {
        ExerciseFilterState.missingEquipment(for: exercise, available: available)
    }

    private var subtitle: String {
        let muscle = exercise.muscleGroup.displayName
        let equipmentNames = exercise.equipment.map(\.name).sorted()
        let equipmentText = equipmentNames.isEmpty ? "Bodyweight" : equipmentNames.joined(separator: ", ")
        return "\(muscle) · \(equipmentText)"
    }
}

// MARK: - Filter Bar

private struct FilterBar: View {
    var filterState: ExerciseFilterState
    @Binding var showingMuscleGroupFilter: Bool
    @Binding var showingEquipmentFilter: Bool

    private var anyFilterActive: Bool {
        !filterState.selectedMuscleGroups.isEmpty || !filterState.selectedEquipment.isEmpty
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if anyFilterActive {
                    ClearAllChip {
                        filterState.selectedMuscleGroups = []
                        filterState.selectedEquipment = []
                    }
                }
                TrayFilterChip(
                    facet: "MUSCLE",
                    count: filterState.selectedMuscleGroups.count
                ) { showingMuscleGroupFilter = true }
                TrayFilterChip(
                    facet: "EQUIPMENT",
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
    /// The catalog browser availability-hides and needs the escape
    /// hatch; the picker doesn't hide, so it passes false (a toggle that
    /// does nothing reads as broken).
    var showsAvailabilityToggle = true

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
                        Text("This filters by the gear in your library. Add what you have on the Equipment tab and it shows up here.")
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

                    // The availability escape hatch lives here now (§H) —
                    // it left the crowded catalog top area.
                    if showsAvailabilityToggle {
                        Toggle(isOn: Bindable(filterState).showUnavailable) {
                            Text("Include gear I don't have")
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.selected)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                        .accessibilityIdentifier("showUnavailableToggle")
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
                    CatalogBrowseScreen(kind: .equipment)
                }
            }
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
    }
}

// MARK: - Selectable Chip

private struct SelectableChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Solid selected blue (#210): one prominent toggled-on look
            // everywhere; ink fills stay reserved for actions.
            Text(label)
                .font(.system(.footnote, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? Theme.selected : Color.clear)
                .foregroundStyle(isSelected ? Theme.onSelected : Theme.textPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.borderStrong, lineWidth: 1))
                .padding(4)
                .contentShape(Rectangle())
        }
        .animation(Theme.Anim.selection, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            height += row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
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

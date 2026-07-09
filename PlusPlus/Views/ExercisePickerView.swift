import SwiftUI
import SwiftData
import PlusPlusKit

// MARK: - Main View

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    var filterState: ExerciseFilterState
    var onSelect: (Exercise) -> Void

    @State private var showingMuscleGroupFilter = false
    @State private var showingEquipmentFilter = false
    @State private var showingCreateSheet = false
    @State private var editingExercise: Exercise?
    @State private var deletionCandidate: Exercise?

    var body: some View {
        NavigationStack {
            List {
                ForEach(filterState.filteredExercises(from: allExercises.filter { $0.inLibrary || !$0.isBuiltIn })) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        ExerciseRow(exercise: exercise)
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
            }
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
                ExerciseEditorView()
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseEditorView(editing: exercise)
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
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    SearchField(prompt: "Search exercises", text: Bindable(filterState).searchText)
                        .padding(.horizontal, 16)
                    FilterBar(
                        filterState: filterState,
                        showingMuscleGroupFilter: $showingMuscleGroupFilter,
                        showingEquipmentFilter: $showingEquipmentFilter
                    )
                }
            }
            .sheet(isPresented: $showingMuscleGroupFilter) {
                MuscleGroupFilterSheet(filterState: filterState)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingEquipmentFilter) {
                EquipmentFilterSheet(filterState: filterState, allEquipment: allEquipment.filter { $0.inLibrary || !$0.isBuiltIn })
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            // Visible only under "show all" (#113): owned exercises
            // never reach this row with missing equipment.
            if !missing.isEmpty {
                Text("needs \(missing.joined(separator: ", "))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.notes)
            }
        }
    }

    private var missing: [String] {
        ExerciseFilterState.missingEquipment(for: exercise)
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
            .animation(.easeOut(duration: 0.15), value: anyFilterActive)
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.bar)
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

                    // The ownership escape hatch lives here now (§H) —
                    // it left the crowded catalog top area.
                    Toggle(isOn: Bindable(filterState).showUnowned) {
                        Text("Include gear I don't own")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.selected)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                    .accessibilityIdentifier("showUnownedToggle")
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
        .animation(.easeOut(duration: 0.15), value: isSelected)
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

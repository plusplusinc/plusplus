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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Exercise", systemImage: "plus") {
                        showingCreateSheet = true
                    }
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
                        allEquipment: allEquipment,
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
        return "Delete “\(exercise.name)”? It appears in \(uses) workout \(uses == 1 ? "entry" : "entries"), which will show as Unknown."
    }

    private func usageCount(of exercise: Exercise) -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<WorkoutExercise>())) ?? []
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
    let allEquipment: [Equipment]
    @Binding var showingMuscleGroupFilter: Bool
    @Binding var showingEquipmentFilter: Bool

    var body: some View {
        VStack(spacing: 6) {
            FilterDropdownButton(
                label: "Muscle Group",
                selections: muscleGroupSelections,
                action: { showingMuscleGroupFilter = true }
            )

            FilterDropdownButton(
                label: "Equipment",
                selections: equipmentSelections,
                action: { showingEquipmentFilter = true }
            )

            // #113: the catalog hides what your equipment can't do;
            // this is the escape hatch.
            Button {
                filterState.showUnowned.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: filterState.showUnowned ? "checkmark.square" : "square")
                        .font(.system(.caption))
                    Text("show exercises needing equipment I don't have")
                        .font(.system(.caption))
                }
                .foregroundStyle(filterState.showUnowned ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("showUnownedToggle")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var muscleGroupSelections: [String] {
        filterState.selectedMuscleGroups
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
    }

    private var equipmentSelections: [String] {
        filterState.selectedEquipment
            .sorted { $0.name < $1.name }
            .map(\.name)
    }
}

private struct FilterDropdownButton: View {
    let label: String
    let selections: [String]
    let action: () -> Void

    private var isActive: Bool { !selections.isEmpty }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                summaryPills
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isActive ? Theme.primaryFill : Theme.border))
        }
        .tint(.primary)
    }

    private var summaryPills: some View {
        Text(selections.isEmpty ? "all" : selections.joined(separator: ", "))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(selections.isEmpty ? Theme.textFaint : Theme.accent)
            .lineLimit(1)
    }
}

// MARK: - Muscle Group Filter Sheet

private struct MuscleGroupFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    var filterState: ExerciseFilterState

    var body: some View {
        NavigationStack {
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
                .padding()
            }
            .navigationTitle("Muscle Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !filterState.selectedMuscleGroups.isEmpty {
                        Button("Clear") {
                            filterState.selectedMuscleGroups.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Equipment Filter Sheet

private struct EquipmentFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    var filterState: ExerciseFilterState
    let allEquipment: [Equipment]

    var body: some View {
        NavigationStack {
            ScrollView {
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
                .padding()
            }
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !filterState.selectedEquipment.isEmpty {
                        Button("Clear") {
                            filterState.selectedEquipment.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Selectable Chip

private struct SelectableChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.footnote, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Theme.primaryFill : Color.clear)
                .foregroundStyle(isSelected ? Theme.onPrimary : Theme.textPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Theme.primaryFill : Theme.borderStrong))
        }
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

import SwiftUI
import SwiftData
import PlusPlusKit

/// Create or edit a custom exercise, in the v2 sheet language (#86):
/// terse sections, chips for muscle group, and equipment presented as
/// explicit "requires all of these" chips. Built-ins are never passed
/// here — they stay read-only.
struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query private var allExercises: [Exercise]

    private let editingExercise: Exercise?
    @State private var draft: ExerciseDraft

    init(editing exercise: Exercise? = nil) {
        editingExercise = exercise
        _draft = State(initialValue: exercise.map(ExerciseDraft.init(from:)) ?? ExerciseDraft())
    }

    /// New custom exercise with the name pre-filled (the Library's
    /// "Create “query”" path, #63).
    init(prefillName: String) {
        editingExercise = nil
        let draft = ExerciseDraft()
        draft.name = prefillName
        _draft = State(initialValue: draft)
    }

    private var existingNames: [String] {
        allExercises.map(\.name)
    }

    private var canSave: Bool {
        draft.canSave(existingNames: existingNames, editedName: editingExercise?.name)
    }

    private var selectedEquipmentSorted: [Equipment] {
        draft.selectedEquipment.sorted { $0.name < $1.name }
    }

    private var unselectedEquipment: [Equipment] {
        allEquipment.filter { !draft.selectedEquipment.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: editingExercise == nil ? "New exercise" : "Edit exercise",
                actionLabel: "Save",
                actionEnabled: canSave,
                actionIdentifier: "saveExerciseButton",
                onCancel: { dismiss() },
                action: { save() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SheetSectionLabel("NAME")
                        .padding(.top, 16)
                    TextField("Exercise name", text: $draft.name)
                        .font(.system(.body))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                        .accessibilityIdentifier("exerciseNameField")
                    if draft.isDuplicate(among: existingNames, excluding: editingExercise?.name) {
                        Text("An exercise with this name already exists.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.destructive)
                            .padding(.top, 6)
                    } else if draft.isRename(of: editingExercise?.name) {
                        Text("Renaming starts a fresh exercise: past sets and \"last time\" stay with \"\(editingExercise?.name ?? "")\".")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.notes)
                            .padding(.top, 6)
                    }

                    SheetSectionLabel("TYPE")
                        .padding(.top, 16)
                    SegmentedTabs(
                        options: ["Weight & reps", "Duration"],
                        selectedIndex: Binding(
                            get: { draft.exerciseType == .duration ? 1 : 0 },
                            set: { draft.exerciseType = $0 == 1 ? .duration : .weightReps }
                        )
                    )

                    SheetSectionLabel("MUSCLE GROUP")
                        .padding(.top, 16)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 7)], spacing: 7) {
                        ForEach(MuscleGroup.allCases) { group in
                            muscleChip(group)
                        }
                    }

                    SheetSectionLabel("REQUIRES")
                        .padding(.top, 16)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 7)], spacing: 7) {
                        ForEach(selectedEquipmentSorted) { equipment in
                            equipmentChip(equipment)
                        }
                        addEquipmentChip
                    }
                    Text(draft.selectedEquipment.isEmpty
                         ? "Bodyweight — no equipment required."
                         : "This exercise needs all of these; filtering by what you own uses it.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("NOTES")
                        .padding(.top, 16)
                    TextField("Form cues, tempo…", text: $draft.notes, axis: .vertical)
                        .font(.system(.footnote))
                        .lineLimit(3...8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                    SheetSectionLabel("VIDEO")
                        .padding(.top, 16)
                    TextField("Link (optional)", text: $draft.videoURL)
                        .font(.system(.footnote))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                    if draft.normalizedVideoURL == .invalid {
                        Text("That doesn't look like a valid link.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.destructive)
                            .padding(.top, 6)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
    }

    private func muscleChip(_ group: MuscleGroup) -> some View {
        let selected = draft.muscleGroup == group
        return Button {
            draft.muscleGroup = group
        } label: {
            Text(group.displayName)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(selected ? Theme.onPrimary : Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.primaryFill : Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.border))
        }
    }

    private func equipmentChip(_ equipment: Equipment) -> some View {
        Button {
            draft.selectedEquipment.remove(equipment)
        } label: {
            HStack(spacing: 5) {
                Text(equipment.name)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
        }
    }

    private var addEquipmentChip: some View {
        Menu {
            ForEach(unselectedEquipment) { equipment in
                Button(equipment.name) {
                    draft.selectedEquipment.insert(equipment)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("+")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Add")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
        .disabled(unselectedEquipment.isEmpty)
    }

    private func save() {
        if let exercise = editingExercise {
            draft.apply(to: exercise)
        } else {
            let exercise = Exercise(name: draft.trimmedName, muscleGroup: draft.muscleGroup)
            modelContext.insert(exercise)
            draft.apply(to: exercise)
        }
        dismiss()
    }
}

/// Read-only exercise details: muscle group, equipment, notes, video link.
/// Reachable from the workout detail screen so form cues are available
/// mid-workout.
struct ExerciseInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Muscle Group", value: exercise.muscleGroup.displayName)
                    LabeledContent(
                        "Equipment",
                        value: exercise.equipment.isEmpty
                            ? "Bodyweight"
                            : exercise.equipment.map(\.name).sorted().joined(separator: ", ")
                    )
                }

                if let notes = exercise.notes {
                    Section("Notes") {
                        Text(notes)
                    }
                }

                if let videoURL = exercise.videoURL, let url = URL(string: videoURL) {
                    Section {
                        Link(destination: url) {
                            Label("Watch video", systemImage: "play.rectangle")
                        }
                    }
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

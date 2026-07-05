import SwiftUI
import SwiftData

/// Create or edit a custom exercise. Built-ins are never passed here —
/// they stay read-only.
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

    private var existingNames: [String] {
        allExercises.map(\.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("exerciseNameField")

                    Picker("Muscle Group", selection: $draft.muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }

                    Picker("Type", selection: $draft.exerciseType) {
                        Text("Weight & Reps").tag(ExerciseType.weightReps)
                        Text("Duration").tag(ExerciseType.duration)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if draft.isDuplicate(among: existingNames, excluding: editingExercise?.name) {
                        Text("An exercise with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Equipment") {
                    ForEach(allEquipment) { equipment in
                        Button {
                            toggle(equipment)
                        } label: {
                            HStack {
                                Text(equipment.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if draft.selectedEquipment.contains(equipment) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.indigo)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Notes (form cues, tempo…)", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)

                    TextField("Video link (optional)", text: $draft.videoURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Details")
                } footer: {
                    if draft.normalizedVideoURL == .invalid {
                        Text("That doesn't look like a valid link.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editingExercise == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave(existingNames: existingNames, editedName: editingExercise?.name))
                        .accessibilityIdentifier("saveExerciseButton")
                }
            }
        }
    }

    private func toggle(_ equipment: Equipment) {
        if draft.selectedEquipment.contains(equipment) {
            draft.selectedEquipment.remove(equipment)
        } else {
            draft.selectedEquipment.insert(equipment)
        }
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

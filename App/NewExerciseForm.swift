import DesignSystem
import SwiftUI
import WorkoutStore

/// New exercise, pushed from the picker's Create: the five settings a created exercise has, and
/// no more. Name, prefilled with the search text and not focused, since the next thing to set is
/// the muscle groups; Muscle groups and Equipment, each one row reading what is checked
/// ("Back, shoulders"; Choose and Bodyweight for none) that opens its full list to check any
/// number on (`Checklist`); Measure; and Per side. All checked groups are equal. Everything else
/// (its weight, plan, rest, and naming) is derived (`Exercise(created:)`).
///
/// Add is off while the name is empty or already an exercise's, or no muscle group is checked
/// (`CreatedExercise.canAdd`), and after its first tap. Cancel goes back to the search as it was;
/// nothing is created before
/// Add.
struct NewExerciseForm: View {
    let exercises: ExerciseList
    let onAdd: (CreatedExercise) async -> Void

    @State private var name: String
    @State private var muscleGroups: Set<MuscleGroup> = []
    @State private var equipment: Set<Equipment> = []
    @State private var measure = Measure.reps
    @State private var isPerSide = false
    @State private var isAdding = false
    @Environment(\.dismiss) private var dismiss

    init(
        name: String,
        exercises: ExerciseList,
        onAdd: @escaping (CreatedExercise) async -> Void,
    ) {
        _name = State(initialValue: name)
        self.exercises = exercises
        self.onAdd = onAdd
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !isAdding
            && CreatedExercise.canAdd(named: name, muscleGroups: muscleGroups, to: exercises)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Name", text: $name)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .accessibilityIdentifier("newExercise.name")
                }
            }
            .listRowBackground(Color.pp(.surface))
            Section {
                NavigationLink {
                    Checklist(
                        title: "Muscle groups",
                        footer: "Check all it works.",
                        checked: $muscleGroups,
                    )
                } label: {
                    LabeledContent("Muscle groups", value: muscleGroups.line ?? "Choose")
                }
                NavigationLink {
                    Checklist(
                        title: "Equipment",
                        footer: "Check all it needs. None means bodyweight.",
                        checked: $equipment,
                    )
                } label: {
                    LabeledContent("Equipment", value: equipment.line ?? "Bodyweight")
                }
            }
            .listRowBackground(Color.pp(.surface))
            Section {
                Picker("Measure", selection: $measure) {
                    ForEach(Measure.allCases, id: \.self) { measure in
                        Text(measure.name).tag(measure)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.pp(.textSecondary))
                Toggle("Per side", isOn: $isPerSide)
            } footer: {
                Text("Each side is its own set, left then right.")
            }
            .listRowBackground(Color.pp(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color.pp(.background))
        .navigationTitle("New exercise")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .disabled(!canAdd)
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        isAdding = true
        let created = CreatedExercise(
            name: trimmedName,
            muscleGroups: muscleGroups,
            equipment: equipment,
            measure: measure,
            isPerSide: isPerSide,
        )
        Task { await onAdd(created) }
    }
}

#Preview {
    NavigationStack {
        NewExerciseForm(name: "Ring row with rotation", exercises: .builtIn) { _ in }
    }
}

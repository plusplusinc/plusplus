import DesignSystem
import SwiftUI
import WorkoutStore

/// New exercise, pushed from the picker's Create: the five settings a created exercise has, and
/// no more. Name, prefilled with the search text and not focused, since the next thing to set is
/// the muscle group; Muscle group, which reads Choose until one is picked; Equipment, one row
/// reading what is checked, or Bodyweight, that opens the full list; Measure; and Per side.
/// Everything else (its weight, plan, rest, and naming) is derived (`Exercise(created:)`).
///
/// Add is off while the name is empty or already an exercise's, or no muscle group is chosen,
/// and after its first tap. Cancel goes back to the search as it was; nothing is created before
/// Add.
struct NewExerciseForm: View {
    let exercises: ExerciseList
    let onAdd: (CreatedExercise) async -> Void

    @State private var name: String
    @State private var muscleGroup: MuscleGroup?
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
        !isAdding && muscleGroup != nil && !trimmedName.isEmpty
            && !exercises.hasExercise(named: trimmedName)
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
                Picker("Muscle group", selection: $muscleGroup) {
                    if muscleGroup == nil {
                        Text("Choose").tag(MuscleGroup?.none)
                    }
                    ForEach(MuscleGroup.allCases, id: \.self) { group in
                        Text(group.name).tag(MuscleGroup?.some(group))
                    }
                }
                .pickerStyle(.menu)
                // Its value reads gray, as the Equipment row's does, not in the system's blue.
                .tint(Color.pp(.textSecondary))
                NavigationLink {
                    EquipmentChecklist(checked: $equipment)
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
        guard canAdd, let muscleGroup else { return }
        isAdding = true
        let created = CreatedExercise(
            name: trimmedName,
            muscleGroup: muscleGroup,
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

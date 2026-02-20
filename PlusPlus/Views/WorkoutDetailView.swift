import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workout: Workout

    @State private var filterState = ExerciseFilterState()
    @State private var showingPicker = false

    var body: some View {
        List {
            ForEach(workout.sortedGroups) { group in
                GroupSection(group: group, modelContext: modelContext, workout: workout)
            }
            .onDelete(perform: deleteGroups)
            .onMove(perform: moveGroups)
        }
        .navigationTitle(workout.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .overlay {
            if workout.groups.isEmpty {
                ContentUnavailableView {
                    Label("No Exercises", systemImage: "dumbbell")
                } description: {
                    Text("Tap below to add exercises to this workout.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showingPicker = true
            } label: {
                Label("Add Exercise", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView(filterState: filterState) { exercise in
                addExercise(exercise)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func addExercise(_ exercise: Exercise) {
        // TODO: Superset UI — add exercise to existing group
        let group = ExerciseGroup(order: workout.groups.count, sets: 3)
        group.workout = workout
        modelContext.insert(group)

        let workoutExercise = WorkoutExercise(exercise: exercise, order: 0)
        workoutExercise.group = group
        modelContext.insert(workoutExercise)

        workout.reindexGroups()
    }

    private func deleteGroups(at offsets: IndexSet) {
        let sorted = workout.sortedGroups
        for index in offsets {
            modelContext.delete(sorted[index])
        }
        workout.reindexGroups()
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        var sorted = workout.sortedGroups
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, group) in sorted.enumerated() {
            group.order = index
        }
    }
}

// MARK: - Group Section

private struct GroupSection: View {
    @Bindable var group: ExerciseGroup
    let modelContext: ModelContext
    let workout: Workout

    var body: some View {
        Section {
            ForEach(group.sortedExercises) { workoutExercise in
                ExerciseInputRow(workoutExercise: workoutExercise)
            }
        } header: {
            HStack {
                if group.isSuperset {
                    Text("Superset")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper("Sets: \(group.sets)", value: $group.sets, in: 1...20)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Exercise Input Row

private struct ExerciseInputRow: View {
    @Bindable var workoutExercise: WorkoutExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workoutExercise.exercise?.name ?? "Unknown")
                .font(.headline)

            if workoutExercise.exercise?.exerciseType == .duration {
                durationInput
            } else {
                weightRepsInput
            }
        }
        .padding(.vertical, 4)
    }

    // TODO: Replace with custom input controls (scroll/stepper)
    private var weightRepsInput: some View {
        HStack(spacing: 16) {
            HStack {
                Text("lbs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Weight", value: $workoutExercise.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            HStack {
                Text("reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Reps", value: $workoutExercise.reps, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }
        }
    }

    // TODO: Replace with custom input controls (scroll/stepper)
    private var durationInput: some View {
        HStack {
            Text("seconds")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Duration", value: $workoutExercise.durationSeconds, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}

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
                GroupSection(
                    group: group,
                    groupCount: workout.sortedGroups.count,
                    onDeleteExercises: { offsets in deleteExercises(at: offsets, in: group) },
                    onDeleteGroup: { deleteGroup(group) },
                    onMoveGroup: { delta in moveGroup(group, by: delta) }
                )
            }
        }
        .navigationTitle(workout.name)
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
            .tint(.indigo)
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView(filterState: filterState) { exercise in
                addExercise(exercise)
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        // TODO: Superset UI (issue #2) — add exercise to existing group
        let group = ExerciseGroup(order: workout.groups.count, sets: 3)
        group.workout = workout
        modelContext.insert(group)

        let workoutExercise = WorkoutExercise(exercise: exercise, order: 0)
        workoutExercise.group = group
        modelContext.insert(workoutExercise)

        workout.reindexGroups()
    }

    private func deleteExercises(at offsets: IndexSet, in group: ExerciseGroup) {
        let sorted = group.sortedExercises
        for index in offsets {
            modelContext.delete(sorted[index])
        }
        group.reindexExercises()
        if group.sortedExercises.isEmpty {
            modelContext.delete(group)
            workout.reindexGroups()
        }
    }

    private func deleteGroup(_ group: ExerciseGroup) {
        modelContext.delete(group)
        workout.reindexGroups()
    }

    private func moveGroup(_ group: ExerciseGroup, by delta: Int) {
        var sorted = workout.sortedGroups
        guard let index = sorted.firstIndex(where: { $0 === group }) else { return }
        let target = index + delta
        guard sorted.indices.contains(target) else { return }
        sorted.swapAt(index, target)
        for (newOrder, moved) in sorted.enumerated() {
            moved.order = newOrder
        }
    }
}

// MARK: - Group Section

private struct GroupSection: View {
    @Bindable var group: ExerciseGroup
    let groupCount: Int
    let onDeleteExercises: (IndexSet) -> Void
    let onDeleteGroup: () -> Void
    let onMoveGroup: (Int) -> Void

    var body: some View {
        Section {
            ForEach(group.sortedExercises) { workoutExercise in
                ExerciseInputRow(workoutExercise: workoutExercise)
            }
            .onDelete(perform: onDeleteExercises)

            Stepper("Sets: \(group.sets)", value: $group.sets, in: 1...20)
        } header: {
            HStack {
                if group.isSuperset {
                    Text("Superset")
                }
                Spacer()
                Menu {
                    Button("Move Up", systemImage: "arrow.up") {
                        onMoveGroup(-1)
                    }
                    .disabled(group.order == 0)

                    Button("Move Down", systemImage: "arrow.down") {
                        onMoveGroup(1)
                    }
                    .disabled(group.order == groupCount - 1)

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onDeleteGroup()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

// MARK: - Exercise Input Row

private struct ExerciseInputRow: View {
    @Bindable var workoutExercise: WorkoutExercise

    @State private var showingInfo = false

    private var hasDetails: Bool {
        workoutExercise.exercise?.notes != nil || workoutExercise.exercise?.videoURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workoutExercise.exercise?.name ?? "Unknown")
                    .font(.headline)
                if hasDetails {
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.indigo)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if workoutExercise.exercise?.exerciseType == .duration {
                MetricRow(metric: .duration, value: intMetricBinding($workoutExercise.durationSeconds))
            } else {
                MetricRow(metric: .weight, value: $workoutExercise.weight)
                RepTargetRow(lower: $workoutExercise.reps, upper: $workoutExercise.repsUpper)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingInfo) {
            if let exercise = workoutExercise.exercise {
                ExerciseInfoView(exercise: exercise)
            }
        }
    }
}

/// Bridges the model's optional Int storage to MetricRow's Double interface.
private func intMetricBinding(_ source: Binding<Int?>) -> Binding<Double?> {
    Binding(
        get: { source.wrappedValue.map(Double.init) },
        set: { source.wrappedValue = $0.map { Int($0.rounded()) } }
    )
}

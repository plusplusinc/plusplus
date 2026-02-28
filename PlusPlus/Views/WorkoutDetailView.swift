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
                if let exercise = group.sortedExercises.first?.exercise {
                    Text(exercise.name)
                }
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

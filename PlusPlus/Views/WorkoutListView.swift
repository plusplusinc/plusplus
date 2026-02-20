import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var workouts: [Workout]

    @State private var path: [Workout] = []
    @State private var showingNewWorkout = false
    @State private var newWorkoutName = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutRow(workout: workout)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteWorkout(workout)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveWorkouts)
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewWorkout = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Tap + to create your first workout.")
                    )
                }
            }
            .alert("New Workout", isPresented: $showingNewWorkout) {
                TextField("Name", text: $newWorkoutName)
                Button("Cancel", role: .cancel) { newWorkoutName = "" }
                Button("Create") { createWorkout() }
            }
        }
    }

    private func createWorkout() {
        let name = newWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        newWorkoutName = ""
        guard !name.isEmpty else { return }

        let workout = Workout(name: name, order: 0)
        modelContext.insert(workout)

        // Push existing workouts down
        for existing in workouts where existing !== workout {
            existing.order += 1
        }

        path.append(workout)
    }

    private func deleteWorkout(_ workout: Workout) {
        modelContext.delete(workout)
        reindexWorkouts()
    }

    private func moveWorkouts(from source: IndexSet, to destination: Int) {
        var reordered = Array(workouts)
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, workout) in reordered.enumerated() {
            workout.order = index
        }
    }

    private func reindexWorkouts() {
        for (index, workout) in workouts.enumerated() {
            workout.order = index
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading) {
            Text(workout.name)
            Text("^[\(workout.groups.count) exercise](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

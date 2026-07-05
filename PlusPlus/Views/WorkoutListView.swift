import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var workouts: [Workout]

    @State private var path: [Workout] = []
    @State private var showingNewWorkout = false
    @State private var newWorkoutName = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutRow(workout: workout)
                    }
                    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 12).inset(by: -16))
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
            .listRowSpacing(8)
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("historyButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationDetents([.medium])
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Create your first workout to get started.")
                    )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { showingNewWorkout = true } label: {
                    Text("++")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .offset(y: -2)
                        .frame(width: 56, height: 56)
                        .background(Color.indigo)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
                .accessibilityIdentifier("newWorkoutButton")
                .padding(24)
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

    private var pills: [String] {
        let names = workout.equipmentNames
        return names.isEmpty ? ["No equipment"] : names
    }

    var body: some View {
        HStack {
            Text(workout.name)
                .font(.title3)
            Spacer()
            HStack(spacing: 6) {
                ForEach(pills, id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

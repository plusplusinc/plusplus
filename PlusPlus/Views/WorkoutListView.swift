import SwiftUI
import SwiftData

/// The Workouts tab, v3 (#109): workout cards with equipment pills and
/// a contextual header + (new workout). Library/History/Settings left
/// this header with the nav restructure — Exercises and Equipment are
/// tabs, history lives on Today, settings opens from Today's header.
struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var workouts: [Workout]

    @State private var path = NavigationPath()
    @State private var showingNewWorkout = false
    @State private var newWorkoutName = ""
    @State private var openSwipeRow: PersistentIdentifier?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                List {
                ForEach(workouts) { workout in
                    SwipeRevealRow(id: workout.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
                        WorkoutCard(workout: workout) {
                            if openSwipeRow != nil { openSwipeRow = nil } else { path.append(workout) }
                        }
                    } actions: {
                        SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                            openSwipeRow = nil
                            deleteWorkout(workout)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                    .onMove(perform: moveWorkouts)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
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
            .alert("New Workout", isPresented: $showingNewWorkout) {
                TextField("Name", text: $newWorkoutName)
                Button("Cancel", role: .cancel) { newWorkoutName = "" }
                Button("Create") { createWorkout() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HeaderGlyph()
                Spacer()
                HeaderIconButton(systemImage: "plus", identifier: "newWorkoutButton") {
                    showingNewWorkout = true
                }
            }
            Text("Workouts")
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
            // Sync caption goes live with #23; until then it points at the plan.
            Text("sync off — connect GitHub in settings")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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

/// 38 pt round icon button used in tab headers.
struct HeaderIconButton: View {
    let systemImage: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 38, height: 38)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
        }
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

private struct WorkoutCard: View {
    let workout: Workout
    let onOpen: () -> Void

    /// Up to two equipment pills plus a "+N" overflow, per the design.
    private var pills: [String] {
        let names = workout.equipmentNames
        guard !names.isEmpty else { return ["bodyweight"] }
        if names.count > 2 {
            return Array(names.prefix(2)) + ["+\(names.count - 2)"]
        }
        return names
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text(workout.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    ForEach(pills, id: \.self) { pill in
                        Text(pill)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .overlay(Capsule().strokeBorder(Theme.borderStrong))
                            .lineLimit(1)
                    }
                }
                .layoutPriority(-1)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
    }
}

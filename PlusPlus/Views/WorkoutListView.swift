import SwiftUI
import SwiftData

/// Home screen, v2 (#60): custom header with the ++ glyph and round icon
/// buttons, workout cards with equipment pills, and a glass FAB. The
/// Library button joins the header when #63 lands.
struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var workouts: [Workout]

    /// Non-workout pushes from the home screen. Everything the stack can
    /// show must flow through the one path binding: mixing a typed path
    /// with navigationDestination(isPresented:) leaves SwiftUI with two
    /// sources of truth it can't reconcile, which livelocks the push.
    private enum HomeDestination: Hashable {
        case history
        case library
    }

    @State private var path = NavigationPath()
    @State private var showingNewWorkout = false
    @State private var newWorkoutName = ""
    @State private var showingSettings = false
    @State private var catalogSheet: AddFromCatalogSheet.Kind?
    @State private var newCustomPrefill: CustomExercisePrefill?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                List {
                    ForEach(workouts) { workout in
                        WorkoutCard(workout: workout) {
                            path.append(workout)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteWorkout(workout)
                            } label: {
                                Label("Delete", systemImage: "xmark")
                            }
                        }
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
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .history: HistoryView()
                case .library: LibraryView()
                }
            }
            .sheet(item: $catalogSheet) { kind in
                AddFromCatalogSheet(kind: kind) { prefill in
                    newCustomPrefill = CustomExercisePrefill(name: prefill)
                }
            }
            .sheet(item: $newCustomPrefill) { prefill in
                ExerciseEditorView(prefillName: prefill.name)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
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
                fab
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
                Text("++")
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                HStack(spacing: 8) {
                    HeaderIconButton(systemImage: "dumbbell", identifier: "libraryButton") {
                        path.append(HomeDestination.library)
                    }
                    HeaderIconButton(systemImage: "clock", identifier: "historyButton") {
                        path.append(HomeDestination.history)
                    }
                    HeaderIconButton(systemImage: "slider.horizontal.3", identifier: "settingsButton") {
                        showingSettings = true
                    }
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

    private var fab: some View {
        Menu {
            Button("New workout", systemImage: "plus") { showingNewWorkout = true }
            Button("Add exercise", systemImage: "figure.strengthtraining.traditional") {
                catalogSheet = .exercises
            }
            Button("Add equipment", systemImage: "dumbbell") {
                catalogSheet = .equipment
            }
        } label: {
            Text("+")
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .offset(y: -1)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.16)))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
        }
        .accessibilityIdentifier("newWorkoutButton")
        .padding(24)
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

/// 38 pt round icon button used in the home header.
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

import SwiftUI
import SwiftData
import PlusPlusKit

/// The Routines tab, v3 (#109): routine cards with equipment pills and
/// a contextual header + (new routine). Library/History/Settings left
/// this header with the nav restructure — Exercises and Equipment are
/// tabs, history lives on Today, settings opens from Today's header.
struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]

    @State private var path = NavigationPath()
    @State private var showingNewRoutine = false
    @State private var newRoutineName = ""
    @State private var openSwipeRow: PersistentIdentifier?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                List {
                ForEach(routines) { routine in
                    SwipeRevealRow(id: routine.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
                        RoutineCard(routine: routine) {
                            if openSwipeRow != nil { openSwipeRow = nil } else { path.append(routine) }
                        }
                    } actions: {
                        SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                            openSwipeRow = nil
                            deleteRoutine(routine)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                    .onMove(perform: moveRoutines)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(routine: routine)
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No Routines",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Create your first routine to get started.")
                    )
                }
            }
            .alert("New Routine", isPresented: $showingNewRoutine) {
                TextField("Name", text: $newRoutineName)
                Button("Cancel", role: .cancel) { newRoutineName = "" }
                Button("Create") { createRoutine() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HeaderGlyph()
                Spacer()
                HeaderIconButton(systemImage: "plus", identifier: "newRoutineButton") {
                    showingNewRoutine = true
                }
            }
            Text("Routines")
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func createRoutine() {
        let name = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        newRoutineName = ""
        guard !name.isEmpty else { return }

        let routine = Routine(name: name, order: 0)
        modelContext.insert(routine)

        // Push existing routines down
        for existing in routines where existing !== routine {
            existing.order += 1
        }

        path.append(routine)
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        reindexRoutines()
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        var reordered = Array(routines)
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in reordered.enumerated() {
            routine.order = index
        }
    }

    private func reindexRoutines() {
        for (index, routine) in routines.enumerated() {
            routine.order = index
        }
    }
}

/// 44 pt round icon button used in tab headers (HIG minimum target).
struct HeaderIconButton: View {
    let systemImage: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
        }
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

private struct RoutineCard: View {
    let routine: Routine
    let onOpen: () -> Void

    private var estimateText: String {
        let minutes = max(5, Int((Double(routine.estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
    }

    /// Up to two equipment pills plus a "+N" overflow, per the design.
    private var pills: [String] {
        let names = routine.equipmentNames
        guard !names.isEmpty else { return ["bodyweight"] }
        if names.count > 2 {
            return Array(names.prefix(2)) + ["+\(names.count - 2)"]
        }
        return names
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(routine.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(estimateText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    // Schedule pill first (#112): the cadence at a glance,
                    // faint when the routine is unscheduled.
                    Text(routine.schedule.shortLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(routine.schedule.normalized == .unscheduled ? Theme.textFaint : Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .overlay(Capsule().strokeBorder(Theme.border))
                        .lineLimit(1)
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

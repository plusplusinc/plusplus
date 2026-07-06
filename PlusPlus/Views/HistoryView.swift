import SwiftUI
import SwiftData
import PlusPlusKit

/// Completed sessions, newest first.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var sessions: [WorkoutSession]

    var body: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    SessionRow(session: session)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        modelContext.delete(session)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("History")
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Workouts Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finished workouts show up here.")
                )
            }
        }
    }
}

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.workoutName)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [session.startedAt.formatted(date: .abbreviated, time: .shortened)]
        let sets = session.completedSetLogs.count
        parts.append("\(sets) \(sets == 1 ? "set" : "sets")")
        if let duration = session.duration {
            parts.append(Self.durationText(duration))
        }
        return parts.joined(separator: " · ")
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return minutes < 1 ? "<1 min" : "\(minutes) min"
    }
}

/// Per-set breakdown of a completed session, grouped the way the workout
/// was structured (superset members share a section).
struct SessionDetailView: View {
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    let session: WorkoutSession

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    private var groupedLogs: [(groupIndex: Int, logs: [SetLog])] {
        let completed = session.completedSetLogs
        let grouped = Dictionary(grouping: completed, by: \.groupIndex)
        return grouped.keys.sorted().map { key in
            (groupIndex: key, logs: grouped[key]!.sorted { $0.order < $1.order })
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let duration = session.duration {
                    LabeledContent("Duration", value: SessionRow.durationText(duration))
                }
                LabeledContent("Sets", value: "\(session.completedSetLogs.count)")
            }

            ForEach(groupedLogs, id: \.groupIndex) { group in
                Section(sectionTitle(for: group.logs)) {
                    ForEach(group.logs) { log in
                        HStack {
                            Text("Set \(log.setNumber)")
                                .foregroundStyle(.secondary)
                            if group.logs.contains(where: { $0.exerciseName != log.exerciseName }) {
                                Text(log.exerciseName)
                                    .font(.subheadline)
                            }
                            Spacer()
                            Text(log.resultSummary(weightUnit: weightUnit))
                                .font(.body.monospacedDigit())
                        }
                    }
                }
            }
        }
        .navigationTitle(session.workoutName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(for logs: [SetLog]) -> String {
        var seen: Set<String> = []
        var names: [String] = []
        for log in logs where !seen.contains(log.exerciseName) {
            seen.insert(log.exerciseName)
            names.append(log.exerciseName)
        }
        return names.joined(separator: " + ")
    }
}

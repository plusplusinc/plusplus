import SwiftUI
import SwiftData
import PlusPlusKit

/// Completed sessions, newest first — v2 (#67): cards under a mono
/// "append-only" caption. No delete affordance: history is the record.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var sessions: [WorkoutSession]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Text("Workouts").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("backButton")

                Text("History")
                    .font(.system(size: 26, weight: .bold))
                    .padding(.top, 2)
                Text("history/\(yearText) · append-only")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            List {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if sessions.isEmpty {
                Text("Finished workouts show up here.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var yearText: String {
        FileLayout.utcDateParts(of: sessions.first?.startedAt ?? Date()).year
    }
}

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.workoutName)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private var subtitle: String {
        var parts = [session.startedAt.formatted(.dateTime.month(.abbreviated).day())]
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
/// was structured (superset members share a block).
struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    let session: WorkoutSession

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    /// Blocks keyed by (group, exercise) in rotation order.
    private var blocks: [(name: String, sets: [SetLog])] {
        var order: [String] = []
        var byKey: [String: (name: String, sets: [SetLog])] = [:]
        for log in session.completedSetLogs {
            let key = "\(log.groupIndex)|\(log.exerciseName)"
            if byKey[key] == nil {
                byKey[key] = (log.exerciseName, [])
                order.append(key)
            }
            byKey[key]?.sets.append(log)
        }
        return order.compactMap { byKey[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Text("History").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 6)
                }

                Text(session.workoutName)
                    .font(.system(size: 24, weight: .bold))
                    .padding(.top, 2)
                Text(subtitle)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(block.name)
                                .font(.system(size: 13.5, weight: .semibold))
                            ForEach(Array(block.sets.enumerated()), id: \.offset) { _, log in
                                HStack {
                                    Text("Set \(log.setNumber)")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(log.resultSummary(weightUnit: weightUnit))
                                        .font(.system(size: 11.5, design: .monospaced))
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var subtitle: String {
        var parts = [session.startedAt.formatted(.dateTime.month(.abbreviated).day())]
        parts.append("\(session.completedSetLogs.count) sets")
        if let duration = session.duration {
            parts.append(SessionRow.durationText(duration))
        }
        return parts.joined(separator: " · ")
    }
}

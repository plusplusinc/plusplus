import SwiftUI
import SwiftData
import PlusPlusKit

// The standalone History screen died with the v3 nav restructure
// (#109): Today's timeline is the record now. The session card and the
// per-set session record live on, rendered from the Today tab.

/// Completed-session card: name + mono "jul 3 · 18 sets · 42 min".
struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.routineName)
                .font(.system(.subheadline, weight: .semibold))
            Text(subtitle)
                .font(.system(.caption, design: .monospaced))
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

/// Per-set breakdown of a completed session, grouped the way the routine
/// was structured (superset members share a block). Block headers carry
/// a mono weight delta against the previous session of the same routine
/// (#110 §3) — neutral gray both directions; deloads are intentional.
struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var allFinished: [WorkoutSession]
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

    /// The previous committed session of the same routine, if any.
    /// Identity wins over the name fallback (same-name routines must not
    /// cross-contaminate), and "previous" is the max endedAt below this
    /// one — the query's startedAt order isn't the comparison order.
    private var previousSession: WorkoutSession? {
        allFinished
            .filter { other in
                guard other !== session else { return false }
                if let a = other.routine, let b = session.routine {
                    return a === b && (other.endedAt ?? .distantPast) < (session.endedAt ?? .distantPast)
                }
                return other.routineName == session.routineName
                    && (other.endedAt ?? .distantPast) < (session.endedAt ?? .distantPast)
            }
            .max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
    }

    private func topWeight(of name: String, in candidate: WorkoutSession) -> Double? {
        let weights = candidate.completedSetLogs
            .filter { $0.exerciseName == name }
            .compactMap(\.actualWeight)
            .filter { $0 > 0 }
        return weights.max()
    }

    private var previousDateText: String {
        (previousSession?.startedAt ?? .now)
            .formatted(.dateTime.month(.abbreviated).day())
            .lowercased()
    }

    /// "+5 lb" / "−5 lb" vs the previous session; nil when there is no
    /// prior data or nothing moved.
    private func blockDelta(_ name: String) -> String? {
        guard let previousSession,
              let now = topWeight(of: name, in: session),
              let before = topWeight(of: name, in: previousSession),
              now != before
        else { return nil }
        return RoutineDiff.summary(deltas: [.weight(now - before)], weightUnit: weightUnit).first?.text
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(.footnote, weight: .bold))
                        Text("Today").font(.system(.footnote, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 6)
                }

                Text(session.routineName)
                    .font(.system(.title3, weight: .bold))
                    .padding(.top, 2)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 0) {
                    if previousSession != nil {
                        Text("Δ vs \(previousDateText) session")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 10)
                    }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(block.name)
                                    .font(.system(.footnote, weight: .semibold))
                                Spacer()
                                if let delta = blockDelta(block.name) {
                                    Text(delta)
                                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            ForEach(Array(block.sets.enumerated()), id: \.offset) { _, log in
                                HStack {
                                    Text("Set \(log.setNumber)")
                                        .font(.system(.caption))
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(log.resultSummary(weightUnit: weightUnit))
                                        .font(.system(.caption, design: .monospaced))
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

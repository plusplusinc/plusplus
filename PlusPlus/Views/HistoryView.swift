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
        if let average = session.averageHeartRate {
            parts.append("\(average) bpm")
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var allFinished: [WorkoutSession]
    @Query private var routines: [Routine]
    let session: WorkoutSession
    /// "Do it again" (Dave, build-45) presents from HERE, state local
    /// to this screen — the routine-detail Start pattern, and load-
    /// bearing: the flash defers ~0.85 s, so a fire can land while a
    /// pop transition is in flight (back tapped mid-flash, or a held
    /// swipe-back). Parked on a SURVIVING screen that state would
    /// wedge its cover forever if the presentation dropped; local
    /// state dies with the pop and the started session rides Today's
    /// orphan salvage instead (swift-reviewer catch).
    @State private var activeSession: WorkoutSession?
    /// The first-workout Health primer, raised by the start gate.
    @State private var healthStartRequest: HealthStartRequest?
    /// Per-workout active energy (kcal), read live from Health when this
    /// record opens — not persisted, so it needs no schema/interchange
    /// change. nil until the query answers, or when Health has nothing.
    @State private var activeEnergy: Int?

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    /// The routine "Do it again" would start: the session's own
    /// routine when it survives, else a name match (the record's join
    /// key everywhere identity is gone). Empty routines can't stage
    /// (the 0-set bug class), so a hollowed-out routine hides the key
    /// rather than presenting one that no-ops.
    private var repeatCandidate: Routine? {
        if let routine = session.routine, !routine.isDeleted, !routine.groups.isEmpty {
            return routine
        }
        return routines.first {
            $0.name.lowercased() == session.routineName.lowercased() && !$0.groups.isEmpty
        }
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
            ScrollView {
                VStack(spacing: 0) {
                    // The Health facts, when there were any — heart rate
                    // and the workout's active energy, in ink like the
                    // rest of the record. Each shows only when present
                    // (denied or no Watch reads as absent, never zero).
                    if session.averageHeartRate != nil || activeEnergy != nil {
                        HStack(spacing: 12) {
                            if let average = session.averageHeartRate {
                                Text("\(Image(systemName: "heart.fill")) \(average) avg\(session.maxHeartRate.map { " · \($0) max" } ?? "")")
                            }
                            if let activeEnergy {
                                Text("\(Image(systemName: "flame.fill")) \(activeEnergy) cal")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                    }
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
        // Title + the record's facts in the chrome (mock 11:
        // "jul 7 · 18 sets · 42 min" under the name).
        .pushedScreenChrome(title: session.routineName, subtitle: subtitle.lowercased(), onBack: { dismiss() })
        // The record's one action (Dave, build-45): run this workout
        // again, in the same dock grammar as routine detail's Start.
        .safeAreaInset(edge: .bottom) {
            if let routine = repeatCandidate {
                StartFlashButton(label: "Do it again", height: 52, identifier: "repeatWorkoutButton") {
                    // Fire-time re-check (the flash defers ~0.85 s;
                    // see TodayView.start for the failure class).
                    guard activeSession == nil, !routine.isDeleted, !routine.groups.isEmpty else { return }
                    HealthStartGate.begin({
                        guard activeSession == nil, !routine.isDeleted, !routine.groups.isEmpty else { return }
                        activeSession = WorkoutSession.start(from: routine, context: modelContext)
                    }, orPresent: { healthStartRequest = $0 })
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .fullScreenCover(item: $activeSession) { started in
            ActiveSessionView(session: started)
        }
        // The one-time Health ask, in front of a "Do it again" start.
        .healthStartPrimer($healthStartRequest)
        // Heart-rate backfill: a session finished before its samples
        // reached Health (watch sync lag, or access granted later)
        // fills in when the record is opened. Idempotent — only runs
        // while the summary is missing.
        .task {
            guard session.averageHeartRate == nil, let endedAt = session.endedAt else { return }
            // effectiveStart, not startedAt: the HR window matches the
            // workout clock (an ad-hoc session excludes its assembly time).
            HeartRateMonitor.summary(from: session.effectiveStart, to: endedAt) { average, peak in
                guard !session.isDeleted else { return }
                if let average { session.averageHeartRate = average }
                if let peak { session.maxHeartRate = peak }
            }
        }
        // Active energy for this workout, read live from Health (not
        // persisted). effectiveStart matches the HR window above.
        .task {
            guard let endedAt = session.endedAt else { return }
            HealthAccess.activeEnergy(from: session.effectiveStart, to: endedAt) { kcal in
                activeEnergy = kcal
            }
        }
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

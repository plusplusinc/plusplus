import Foundation
import SwiftData
import PlusPlusKit

/// The phone side of live mirror (#322). The phone is the durable system
/// of record (SwiftData), so it keeps NO parallel reducer — `LiveSession`
/// ops are purely the wire format. Outbound: each mutation on the open
/// session emits an op the watch folds into its reducer. Inbound: watch
/// ops project straight onto SwiftData through `project(_:into:)`, which
/// is idempotent and context-agnostic so a DURABLE transfer can be
/// applied synchronously inside the WCSession delegate callback (the A4
/// "acks on return" rule) while a LIVE message updates the open session
/// on the main actor.
@MainActor
final class LiveMirror {
    static let shared = LiveMirror()

    /// Posted (with the rest `endsAt` Date as object, or nil to clear)
    /// when a WATCH op changes the rest state of the session the phone is
    /// showing — the open ActiveSessionView reflects it. Same pattern as
    /// `.plusplusAdjustRest`.
    static let restChanged = Notification.Name("plusplusRemoteRestChanged")

    private var container: ModelContainer?
    /// The session the phone is actively authoring, if any.
    private var activeId: UUID?
    /// Per-origin monotonic sequence (origination = 0).
    private var seq = 0

    /// Idempotent; safe to call from app init.
    func activate(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Outbound (the phone is authoring)

    /// Begins mirroring the open session: resets the op log and emits the
    /// `.started` op carrying the plan, so a watch that never saw this
    /// session can materialize it.
    func begin(_ session: WorkoutSession) {
        guard !session.isFinished else { return }
        activeId = session.sessionId
        seq = 0
        emit(session, .started(
            routineName: session.routineName,
            startedAt: session.effectiveStart,
            restSeconds: session.restSeconds,
            steps: Self.steps(for: session)
        ))
    }

    func logged(_ log: SetLog, in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .logSet(
            index: log.order,
            actualWeight: log.actualWeight,
            actualReps: log.actualReps,
            actualDuration: log.actualDuration,
            extras: MetricValues.toRaw(log.extraActuals) ?? [:],
            completedAt: log.completedAt ?? Date()
        ))
    }

    func reopened(_ log: SetLog, in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .reopen(index: log.order))
    }

    func cursorMoved(to order: Int, in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .cursor(index: order))
    }

    func restStarted(endsAt: Date, total: Int, in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .restStarted(endsAt: endsAt, total: total))
    }

    func restEnded(in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .restEnded)
    }

    func finished(_ session: WorkoutSession, at date: Date) {
        guard session.sessionId == activeId else { return }
        emit(session, .finished(endedAt: date))
        end()
    }

    func discarded(_ session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .discarded)
        end()
    }

    /// Stops authoring — the workout is over on this device.
    private func end() {
        activeId = nil
    }

    private func emit(_ session: WorkoutSession, _ kind: LiveSession.Kind) {
        seq += 1
        let op = LiveSession.Op(
            opId: UUID(),
            sessionId: session.sessionId,
            origin: .phone,
            seq: seq,
            at: Date(),
            kind: kind
        )
        WatchBridge.shared.sendLive(op: op)
    }

    // MARK: - Inbound (the watch is authoring)

    /// A live op arrived over the reachable channel. Projects it onto the
    /// main store and, when it touches the open session, nudges the UI.
    func ingestLive(_ op: LiveSession.Op) {
        guard let container else { return }
        Self.project(op, into: container.mainContext)
        guard op.sessionId == activeId else {
            // A watch-born session the phone isn't showing: it materialized
            // in the store above and will appear on Today as resumable.
            return
        }
        switch op.kind {
        case let .restStarted(endsAt, _):
            NotificationCenter.default.post(name: Self.restChanged, object: endsAt)
        case .restEnded:
            NotificationCenter.default.post(name: Self.restChanged, object: nil)
        default:
            break
        }
    }

    // MARK: - Plan projection into the live session's steps

    private static func steps(for session: WorkoutSession) -> [WatchSync.Step] {
        let maxHR = HealthAccess.resolvedMaxHeartRate()
        return session.sortedSetLogs.map { log in
            let profile = log.metricProfile
            let band = log.targetHeartRate.map { $0.bpmRange(maxHeartRate: maxHR) }
            let extras = log.extraTargets.filter { profile.contains($0.key) }
            return WatchSync.Step(
                exerciseName: log.exerciseName,
                groupIndex: log.groupIndex,
                setNumber: log.setNumber,
                isDuration: profile.legacyType == .duration,
                targetWeight: log.targetWeight,
                targetRepsLower: log.targetRepsLower,
                targetRepsUpper: log.targetRepsUpper,
                targetDuration: log.targetDuration,
                targetHeartRateLowerBPM: band?.lowerBound,
                targetHeartRateUpperBPM: band?.upperBound,
                extraTargets: MetricValues.toRaw(extras),
                distanceUnit: extras.isEmpty ? nil : profile.distanceUnit,
                restSecondsOverride: log.restSecondsOverride,
                isOutdoor: profile.isOutdoor ? true : nil
            )
        }
    }

    // MARK: - Store projection (context-agnostic, idempotent)

    /// Applies one op to `context`. `nonisolated` so the durable transfer
    /// path can run it synchronously on the WCSession delegate queue (a
    /// ModelContext is usable on its creating thread). Idempotent by
    /// construction (value writes, timestamp-LWW on a set slot), so no
    /// path double-applies. A `.started` for an unseen session
    /// materializes it in-progress.
    nonisolated static func project(_ op: LiveSession.Op, into context: ModelContext) {
        let sessionId = op.sessionId
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        descriptor.fetchLimit = 1
        let session = (try? context.fetch(descriptor))?.first

        switch op.kind {
        case let .started(routineName, startedAt, restSeconds, steps):
            guard session == nil else { return } // already materialized
            materialize(sessionId: sessionId, routineName: routineName, startedAt: startedAt, restSeconds: restSeconds, steps: steps, into: context)
        case let .logSet(index, w, r, d, extras, completedAt):
            guard let session, let log = session.sortedSetLogs.first(where: { $0.order == index }) else { return }
            // Timestamp LWW on the slot: a stale redelivery never clobbers
            // a newer completion.
            if let existing = log.completedAt, existing > completedAt { return }
            log.actualWeight = w
            log.actualReps = r
            log.actualDuration = d
            let extraValues = MetricValues.fromRaw(extras)
            if !extraValues.isEmpty { log.extraActuals = extraValues }
            log.completedAt = completedAt
            // Advance the cursor the way the phone's own complete() does.
            let pending = session.sortedSetLogs.filter { !$0.isCompleted }
            session.cursorOrder = (pending.first { $0.order > index } ?? pending.first)?.order ?? session.cursorOrder
        case let .reopen(index):
            guard let session, let log = session.sortedSetLogs.first(where: { $0.order == index }) else { return }
            log.completedAt = nil
            session.cursorOrder = index
        case let .cursor(index):
            session?.cursorOrder = index
        case .restStarted, .restEnded:
            break // rest is view state on the phone, not stored
        case let .finished(endedAt):
            guard let session, !session.isFinished else { return }
            session.finish(at: endedAt)
        case .discarded:
            if let session { context.delete(session) }
        }
        try? context.save()
    }

    nonisolated private static func materialize(sessionId: UUID, routineName: String, startedAt: Date, restSeconds: Int, steps: [WatchSync.Step], into context: ModelContext) {
        let session = WorkoutSession(routineName: routineName, startedAt: startedAt, restSeconds: restSeconds)
        // The `.started` op predates transitions (#369), so snapshot the
        // routine's own setting by name — it covers a custody switch to
        // the phone mid-run. A scratch name resolves nothing and keeps
        // the default.
        if let routine = try? context.fetch(
            FetchDescriptor<Routine>(predicate: #Predicate { $0.name == routineName })
        ).first {
            session.transitionSeconds = routine.transitionSeconds
        }
        session.sessionId = sessionId
        session.startClock(at: startedAt)
        context.insert(session)
        for (order, step) in steps.enumerated() {
            let heartTarget: HeartRateTarget? = {
                guard let lower = step.targetHeartRateLowerBPM, let upper = step.targetHeartRateUpperBPM else { return nil }
                return .range(lowerBPM: lower, upperBPM: upper)
            }()
            let log = SetLog(
                order: order,
                groupIndex: step.groupIndex,
                setNumber: step.setNumber,
                exerciseName: step.exerciseName,
                exerciseType: step.isDuration ? .duration : .weightReps,
                targetWeight: step.targetWeight,
                targetRepsLower: step.targetRepsLower,
                targetRepsUpper: step.targetRepsUpper,
                targetDuration: step.targetDuration,
                targetHeartRateData: heartTarget.flatMap { try? JSONEncoder().encode($0) }
            )
            let extras = MetricValues.fromRaw(step.extraTargets)
            if !extras.isEmpty {
                log.extraTargets = extras
                var metrics = Array(extras.keys)
                if step.targetWeight != nil { metrics.append(.weight) }
                if step.targetRepsLower != nil { metrics.append(.reps) }
                if step.targetDuration != nil { metrics.append(.duration) }
                log.metricsData = MetricProfile(metrics, distanceUnit: step.distanceUnit ?? .meters).encoded()
            }
            log.restSecondsOverride = step.restSecondsOverride
            // Insert first, relationship after (SwiftData rule).
            context.insert(log)
            log.session = session
        }
        try? context.save()
    }
}

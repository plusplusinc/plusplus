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
        Self.setPhoneAuthoring(session.sessionId)
        seq = 0
        emit(session, .started(
            routineName: session.routineName,
            startedAt: session.effectiveStart,
            restSeconds: session.restSeconds,
            steps: Self.steps(for: session),
            routineUuid: session.routine?.uuid
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

    func paused(at date: Date, in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .paused(at: date))
    }

    func resumed(at date: Date, in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .resumed(at: date))
    }

    /// The step list changed mid-session — an added exercise, a swap, a
    /// resize (#512). Re-ships the whole list, `.started`-style: small,
    /// and replacement is idempotent where a diff would need its own
    /// ordering protocol.
    func stepsChanged(in session: WorkoutSession) {
        guard session.sessionId == activeId else { return }
        emit(session, .stepsChanged(steps: Self.steps(for: session)))
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

    /// Emits a lifecycle op for a session this phone is NOT actively
    /// authoring — the salvage path, closing the wrist's journal for a
    /// session whose own Finish/Discard never happened (a crash, or a
    /// dismissal the exit dialog never saw). Without it a dead wrist
    /// journal silently swallowed every future phone session's ops
    /// (stage 1, #510).
    func closeRemotely(_ session: WorkoutSession, discarded: Bool) {
        Self.clearRemoteActivity(session.sessionId)
        if discarded {
            emit(session, .discarded)
        } else {
            emit(session, .finished(endedAt: session.endedAt ?? Date()))
        }
    }

    /// Stops authoring — the workout is over on this device.
    private func end() {
        activeId = nil
        Self.setPhoneAuthoring(nil)
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
                isOutdoor: profile.isOutdoor ? true : nil,
                modality: log.modality
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
        // Every projected op came from the wrist, so its arrival is the
        // proof a wrist session is live — what exempts it from Today's
        // orphan salvage (stage 1, #510). Lifecycle ops clear the entry
        // in their own case bodies AFTER applying, so the clear can't be
        // undone by the ledger write that follows it (#512).
        switch op.kind {
        case .finished, .discarded: break
        default: noteRemoteActivity(sessionId)
        }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        descriptor.fetchLimit = 1
        let session = (try? context.fetch(descriptor))?.first

        // Idempotence + ordering (#512): the sendMessage error-fallback
        // CAN deliver an op twice, and a reachability flip can deliver a
        // live op before its queued `.started`. A duplicate returns; an
        // early op parks durably and replays when its session appears.
        if hasApplied(op) { return }
        var isStartedOp = false
        if case .started = op.kind { isStartedOp = true }
        if session == nil, !isStartedOp {
            bufferPending(op)
            return
        }

        switch op.kind {
        case let .started(routineName, startedAt, restSeconds, steps, routineUuid):
            guard session == nil else { return } // already materialized
            materialize(sessionId: sessionId, routineName: routineName, startedAt: startedAt, restSeconds: restSeconds, steps: steps, routineUuid: routineUuid, into: context)
            markApplied(op)
            drainPending(for: sessionId, into: context)
            return
        case let .logSet(index, w, r, d, extras, completedAt):
            // On a FINISHED session a late op may only FILL A HOLE (an
            // un-completed log — a set the ops lost that no result will
            // ever repair, e.g. an abandoned wrist session salvage
            // closed), never rewrite a committed set (stage 1, #510).
            guard let session,
                  let log = session.sortedSetLogs.first(where: { $0.order == index }),
                  !session.isFinished || log.completedAt == nil else { return }
            // Timestamp LWW on the slot: a stale redelivery never clobbers
            // a newer completion.
            if let existing = log.completedAt, existing > completedAt { return }
            log.actualWeight = w
            log.actualReps = r
            log.actualDuration = d
            let extraValues = MetricValues.fromRaw(extras)
            if !extraValues.isEmpty {
                log.extraActuals = extraValues
                // A measured extra on an untargeted step must still be a
                // tracked metric, or the record can't render what it holds
                // — importResult's own rule, arriving here (stage 1, B17).
                // ⚠️ Carry isOutdoor/paceReference through: the init
                // defaults them, and a widened outdoor profile that lost
                // its flag would re-file the workout in Health.
                let profile = log.metricProfile
                let newKeys = extraValues.keys.filter { !profile.contains($0) }
                if !newKeys.isEmpty {
                    log.metricsData = MetricProfile(
                        profile.metrics + newKeys,
                        distanceUnit: profile.distanceUnit,
                        isOutdoor: profile.isOutdoor,
                        paceReference: profile.paceReference
                    ).encoded()
                }
            }
            log.completedAt = completedAt
            // Advance the cursor the way the phone's own complete() does —
            // on a live session only; a committed record has no cursor.
            if !session.isFinished {
                let pending = session.sortedSetLogs.filter { !$0.isCompleted }
                session.cursorOrder = (pending.first { $0.order > index } ?? pending.first)?.order ?? session.cursorOrder
            }
        case let .reopen(index):
            guard let session, !session.isFinished,
                  let log = session.sortedSetLogs.first(where: { $0.order == index }) else { return }
            log.completedAt = nil
            session.cursorOrder = index
        case let .cursor(index):
            guard let session, !session.isFinished else { return }
            session.cursorOrder = index
        case .restStarted, .restEnded:
            break // rest is view state on the phone, not stored
        case let .finished(endedAt):
            // ⚠️ The wrist ending its share of an ADOPTED session must not
            // end the workout the phone user is still in (#511) — and this
            // op, not the result import, is what arrives first, so the
            // guard lives HERE. Their own Finish closes it; the result
            // merge fills the wrist's data either way. The lifecycle
            // cleanup replaces markApplied: a redelivery refuses on
            // isFinished, and the dead session keeps no ledger.
            guard let session, !session.isFinished,
                  !phoneIsAuthoring(session.sessionId) else { return }
            session.finish(at: endedAt)
            clearRemoteActivity(sessionId)
            try? context.save()
            return
        case .discarded:
            guard let session, !phoneIsAuthoring(session.sessionId) else { return }
            context.delete(session)
            clearRemoteActivity(sessionId)
            try? context.save()
            return
        case let .paused(at):
            // Mirror the pause into the row's own running-time ledger, so
            // a wrist-paused stretch is not banked as active time (#512).
            guard let session, !session.isFinished else { return }
            session.pauseClock(at: at)
        case let .resumed(at):
            guard let session, !session.isFinished else { return }
            session.startClock(at: at)
        case .stepsChanged:
            // The wrist has no structure-editing surface today; a future
            // peer's change lands via the result import. Deliberate no-op.
            break
        }
        markApplied(op)
        try? context.save()
    }

    // MARK: - Live-elsewhere registry (stage 1, #510)

    /// sessionIds whose ops have been arriving from the wrist, with the
    /// last arrival — how salvage tells "running on the wrist right now"
    /// from "crashed last week". UserDefaults so a phone relaunch still
    /// knows before the next op lands; entries clear on lifecycle ops and
    /// on result import, and prune past twice the window.
    private nonisolated static let liveElsewhereKey = "liveMirrorLiveElsewhere"
    /// A wrist session this stale with no ops is no longer live — salvage
    /// may take it, with the honest last-activity anchor.
    private nonisolated static let liveElsewhereWindow: TimeInterval = 12 * 3600
    /// The session the PHONE is actively authoring, readable from the
    /// WCSession delegate queue (#511): the result-import merge must
    /// never end a session the phone user is mid-workout in. In-memory
    /// only — process death ends authoring by definition.
    private nonisolated(unsafe) static var phoneAuthoringId: UUID?

    nonisolated static func phoneIsAuthoring(_ sessionId: UUID) -> Bool {
        registryLock.lock(); defer { registryLock.unlock() }
        return phoneAuthoringId == sessionId
    }

    nonisolated fileprivate static func setPhoneAuthoring(_ sessionId: UUID?) {
        registryLock.lock(); defer { registryLock.unlock() }
        phoneAuthoringId = sessionId
    }
    /// The registry mutates from the WCSession delegate queue AND the
    /// main actor; an unlocked read-modify-write could drop a fresh
    /// session's only entry and hand it back to salvage — the exact bug
    /// this registry exists to fix, made intermittent (swift-reviewer).
    private nonisolated static let registryLock = NSLock()

    nonisolated static func noteRemoteActivity(_ sessionId: UUID, at date: Date = Date()) {
        registryLock.lock(); defer { registryLock.unlock() }
        var map = (UserDefaults.standard.dictionary(forKey: liveElsewhereKey) as? [String: Double]) ?? [:]
        map[sessionId.uuidString] = date.timeIntervalSince1970
        let floor = Date().addingTimeInterval(-2 * liveElsewhereWindow).timeIntervalSince1970
        map = map.filter { $0.value > floor }
        UserDefaults.standard.set(map, forKey: liveElsewhereKey)
    }

    nonisolated static func clearRemoteActivity(_ sessionId: UUID) {
        registryLock.lock(); defer { registryLock.unlock() }
        var map = (UserDefaults.standard.dictionary(forKey: liveElsewhereKey) as? [String: Double]) ?? [:]
        if map.removeValue(forKey: sessionId.uuidString) != nil {
            UserDefaults.standard.set(map, forKey: liveElsewhereKey)
        }
        // The session's lifecycle is over: its op ledger and any parked
        // ops go with it (#512).
        var ledger = (UserDefaults.standard.dictionary(forKey: appliedKey) as? [String: [String]]) ?? [:]
        if ledger.removeValue(forKey: sessionId.uuidString) != nil {
            UserDefaults.standard.set(ledger, forKey: appliedKey)
        }
        var parked = (UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: [Data]]) ?? [:]
        if parked.removeValue(forKey: sessionId.uuidString) != nil {
            UserDefaults.standard.set(parked, forKey: pendingKey)
        }
    }

    // MARK: - Applied-op ledger + pending buffer (stage 3, #512)

    /// The reducer discipline the watch has, arriving on the phone:
    /// duplicates refuse by opId, and ops that outran their `.started`
    /// park durably until it lands. Both maps are bounded (per-session
    /// caps, whole-session cleanup on lifecycle) and UserDefaults-backed
    /// so the A4 ack-on-return guarantee still holds across a relaunch.
    private nonisolated static let appliedKey = "liveMirrorAppliedOps"
    private nonisolated static let pendingKey = "liveMirrorPendingOps"
    private nonisolated static let appliedCapPerSession = 512
    private nonisolated static let pendingCapPerSession = 64
    /// Sessions whose lifecycle op never arrives are pruned oldest-map-
    /// first past this many tracked sessions — a backstop, not a policy.
    private nonisolated static let ledgerSessionCap = 8

    nonisolated private static func hasApplied(_ op: LiveSession.Op) -> Bool {
        registryLock.lock(); defer { registryLock.unlock() }
        let ledger = (UserDefaults.standard.dictionary(forKey: appliedKey) as? [String: [String]]) ?? [:]
        return ledger[op.sessionId.uuidString]?.contains(op.opId.uuidString) ?? false
    }

    nonisolated private static func markApplied(_ op: LiveSession.Op) {
        registryLock.lock(); defer { registryLock.unlock() }
        var ledger = (UserDefaults.standard.dictionary(forKey: appliedKey) as? [String: [String]]) ?? [:]
        var ids = ledger[op.sessionId.uuidString] ?? []
        guard !ids.contains(op.opId.uuidString) else { return }
        ids.append(op.opId.uuidString)
        if ids.count > appliedCapPerSession { ids.removeFirst(ids.count - appliedCapPerSession) }
        ledger[op.sessionId.uuidString] = ids
        while ledger.count > ledgerSessionCap, let victim = ledger.keys.first(where: { $0 != op.sessionId.uuidString }) {
            ledger.removeValue(forKey: victim)
        }
        UserDefaults.standard.set(ledger, forKey: appliedKey)
    }

    nonisolated private static func bufferPending(_ op: LiveSession.Op) {
        guard let data = try? WatchSync.encode(op) else { return }
        registryLock.lock(); defer { registryLock.unlock() }
        var parked = (UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: [Data]]) ?? [:]
        var queue = parked[op.sessionId.uuidString] ?? []
        queue.append(data)
        if queue.count > pendingCapPerSession { queue.removeFirst(queue.count - pendingCapPerSession) }
        parked[op.sessionId.uuidString] = queue
        UserDefaults.standard.set(parked, forKey: pendingKey)
    }

    nonisolated private static func drainPending(for sessionId: UUID, into context: ModelContext) {
        registryLock.lock()
        var parked = (UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: [Data]]) ?? [:]
        let queue = parked.removeValue(forKey: sessionId.uuidString) ?? []
        if !queue.isEmpty { UserDefaults.standard.set(parked, forKey: pendingKey) }
        registryLock.unlock()
        // Replay OUTSIDE the lock — each op re-enters project(), which
        // takes it again per helper.
        for data in queue {
            guard let op = try? WatchSync.decode(LiveSession.Op.self, from: data) else { continue }
            project(op, into: context)
        }
    }

    nonisolated static func isLiveElsewhere(_ sessionId: UUID) -> Bool {
        registryLock.lock(); defer { registryLock.unlock() }
        guard let map = UserDefaults.standard.dictionary(forKey: liveElsewhereKey) as? [String: Double],
              let last = map[sessionId.uuidString] else { return false }
        return Date().timeIntervalSince1970 - last < liveElsewhereWindow
    }

    nonisolated private static func materialize(sessionId: UUID, routineName: String, startedAt: Date, restSeconds: Int, steps: [WatchSync.Step], routineUuid: UUID?, into context: ModelContext) {
        let session = WorkoutSession(routineName: routineName, startedAt: startedAt, restSeconds: restSeconds)
        // The `.started` op predates transitions (#369), so snapshot the
        // routine's own setting — by its stable uuid when the op carries
        // one (#511; names are not unique), by name for older peers. A
        // scratch name resolves nothing and keeps the default.
        let byUuid = routineUuid.flatMap { uuid in
            (try? context.fetch(
                FetchDescriptor<Routine>(predicate: #Predicate { $0.uuid == uuid })
            ))?.first
        }
        let byName = byUuid == nil ? (try? context.fetch(
            FetchDescriptor<Routine>(predicate: #Predicate { $0.name == routineName })
        ))?.first : nil
        if let routine = byUuid ?? byName {
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

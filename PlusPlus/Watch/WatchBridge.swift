import Foundation
import OSLog
import SwiftData
import WatchConnectivity
import PlusPlusKit

/// The phone side of watch sync (#6): pushes the routine plan whenever
/// it may have changed (launch, backgrounding) via
/// updateApplicationContext — latest-wins, delivered even when the
/// watch app is closed — and imports finished wrist sessions arriving
/// via transferUserInfo into SwiftData as ordinary append-only history.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var container: ModelContainer?

    /// Idempotent; safe to call from app init.
    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            pushPlan()
        }
    }

    /// Encodes every routine in its execution order (the same superset
    /// rotation the phone's session factory produces) and ships it.
    func pushPlan() {
        guard let container, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        Task { @MainActor in
            let context = container.mainContext
            let routines = (try? context.fetch(
                FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)])
            )) ?? []
            // Heart-rate targets ship RESOLVED to bpm: the phone holds
            // the max HR (Health's date of birth); the wrist only
            // compares numbers.
            let maxHeartRate = HealthAccess.resolvedMaxHeartRate()
            let plan = WatchSync.Plan(
                generatedAt: Date(),
                routines: routines.map { Self.planRoutine($0, maxHeartRate: maxHeartRate) }
            )
            do {
                let data = try WatchSync.encode(plan)
                try session.updateApplicationContext(["plan": data])
            } catch {
                // Most likely payloadTooLarge on a huge program (~65 KB
                // cap): the watch silently staying stale is the failure
                // mode to make visible (bug hunt A5).
                Logger(subsystem: "com.davidcole.plusplus", category: "watch")
                    .error("plan push failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private static func planRoutine(_ routine: Routine, maxHeartRate: Int) -> WatchSync.PlanRoutine {
        var steps: [WatchSync.Step] = []
        for (groupIndex, group) in routine.sortedGroups.enumerated() {
            for setNumber in 1...max(group.sets, 1) {
                for entry in group.sortedExercises {
                    guard let exercise = entry.exercise else { continue }
                    let heartBand = entry.heartRateTarget.map { $0.bpmRange(maxHeartRate: maxHeartRate) }
                    let profile = exercise.metricProfile
                    let extras = entry.extraTargets.filter { profile.contains($0.key) }
                    steps.append(WatchSync.Step(
                        exerciseName: exercise.name,
                        groupIndex: groupIndex,
                        setNumber: setNumber,
                        isDuration: profile.legacyType == .duration,
                        targetWeight: entry.weight,
                        targetRepsLower: entry.reps,
                        targetRepsUpper: entry.repsUpper,
                        targetDuration: entry.durationSeconds,
                        targetHeartRateLowerBPM: heartBand?.lowerBound,
                        targetHeartRateUpperBPM: heartBand?.upperBound,
                        extraTargets: MetricValues.toRaw(extras),
                        distanceUnit: extras.isEmpty ? nil : profile.distanceUnit,
                        restSecondsOverride: group.restSecondsOverride,
                        isOutdoor: profile.isOutdoor ? true : nil,
                        modality: exercise.modality
                    ))
                }
            }
        }
        return WatchSync.PlanRoutine(
            name: routine.name,
            restSeconds: routine.restSeconds,
            transitionSeconds: routine.transitionSeconds,
            steps: steps
        )
    }

    // MARK: - Live mirror (#322)

    /// Sends one live-mirror op to the watch: `sendMessage` when the wrist
    /// is reachable (sub-second), else the durable `transferUserInfo`
    /// queue so an op made while the watch is in a tunnel/locker is never
    /// lost — it just arrives when the watch next runs. The reachable path
    /// falls back to the queue on failure for the same reason.
    func sendLive(op: LiveSession.Op) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? WatchSync.encode(op) else { return }
        if session.isReachable {
            session.sendMessage(["liveOp": data], replyHandler: nil) { _ in
                session.transferUserInfo(["liveOp": data])
            }
        } else {
            session.transferUserInfo(["liveOp": data])
        }
    }

    /// Live op over the reachable channel: not durable, so no A4 concern —
    /// hand it to the mirror on the main actor to project + nudge the UI.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["liveOp"] as? Data,
              let op = try? WatchSync.decode(LiveSession.Op.self, from: data) else { return }
        Task { @MainActor in LiveMirror.shared.ingestLive(op) }
    }

    // MARK: - Receiving results

    /// IMPORTANT: WCSession marks the transfer delivered when this
    /// method RETURNS — anything deferred past that point can drop a
    /// once-delivered routine forever (bug hunt A4). So both the durable
    /// live op and the finished-session import run synchronously, on this
    /// queue, in a context created here (a ModelContext is usable on its
    /// creating thread).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // A durable live-mirror op (queued while the watch was unreachable).
        if let opData = userInfo["liveOp"] as? Data,
           let op = try? WatchSync.decode(LiveSession.Op.self, from: opData) {
            guard let container else {
                Logger(subsystem: "com.davidcole.plusplus", category: "watch")
                    .fault("live op arrived before activate(container:) — dropped")
                return
            }
            LiveMirror.project(op, into: ModelContext(container))
            return
        }
        guard let data = userInfo["sessionResult"] as? Data else { return }
        guard let container else {
            Logger(subsystem: "com.davidcole.plusplus", category: "watch")
                .fault("session result arrived before activate(container:) — dropped")
            return
        }
        guard let result = try? WatchSync.decode(WatchSync.SessionResult.self, from: data) else {
            Logger(subsystem: "com.davidcole.plusplus", category: "watch")
                .error("undecodable session result (version skew?) — dropped")
            return
        }
        importResult(result, into: ModelContext(container))
    }

    /// Appends the wrist session as ordinary history — or, when the live
    /// mirror already materialized the same session, MERGES into that row
    /// instead (stage 1, #510): the ops carry no heart rate and can
    /// under-carry extras, so skipping the result here threw away the
    /// HR summary on every mirrored wrist workout. Idempotent either way:
    /// transferUserInfo retries across launches, and a re-delivered
    /// result merges the same values onto the same row.
    private func importResult(_ result: WatchSync.SessionResult, into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        if let match = existing.first(where: {
            $0.routineName == result.routineName
                && abs($0.startedAt.timeIntervalSince(result.startedAt)) < 1
        }) {
            merge(result, into: match, context: context)
            return
        }

        let session = WorkoutSession(
            routineName: result.routineName,
            startedAt: result.startedAt,
            restSeconds: result.restSeconds
        )
        context.insert(session)
        // The wrist's live-builder summary; nil when Health said no
        // there. The phone never re-derives it for watch sessions —
        // the builder's numbers are the closest to the sensor.
        session.averageHeartRate = result.averageHeartRate
        session.maxHeartRate = result.maxHeartRate
        for (order, stepResult) in result.steps.enumerated() {
            // The plan resolved any zone target to bpm before the push,
            // so the snapshot here is the band the wrist actually
            // showed — an explicit range, faithfully.
            let heartTarget: HeartRateTarget? = {
                guard let lower = stepResult.step.targetHeartRateLowerBPM,
                      let upper = stepResult.step.targetHeartRateUpperBPM else { return nil }
                return .range(lowerBPM: lower, upperBPM: upper)
            }()
            let log = SetLog(
                order: order,
                groupIndex: stepResult.step.groupIndex,
                setNumber: stepResult.step.setNumber,
                exerciseName: stepResult.step.exerciseName,
                exerciseType: stepResult.step.isDuration ? .duration : .weightReps,
                targetWeight: stepResult.step.targetWeight,
                targetRepsLower: stepResult.step.targetRepsLower,
                targetRepsUpper: stepResult.step.targetRepsUpper,
                targetDuration: stepResult.step.targetDuration,
                targetHeartRateData: heartTarget.flatMap { try? JSONEncoder().encode($0) }
            )
            log.actualWeight = stepResult.actualWeight
            log.actualReps = stepResult.actualReps
            log.actualDuration = stepResult.actualDuration
            log.completedAt = stepResult.completedAt
            // The wrist wears the sensor, so a watch-logged set carries
            // the same per-set heart-rate fact a phone-logged one does.
            // Absent from an older watch build, which stays nil.
            log.actualAverageHeartRate = stepResult.averageHeartRate
            log.actualMaxHeartRate = stepResult.maxHeartRate
            let extras = MetricValues.fromRaw(stepResult.step.extraTargets)
            // What the wrist MEASURED, which is a different thing from
            // what it was asked to do.
            //
            // ⚠️ This used to be `log.extraActuals = extras` — the step's
            // own targets, recorded as though they had happened. A 500 m
            // piece rowed to 412 m came home as 500 m. A result from a
            // watch build that predates `extraActuals` now records no
            // extra actuals at all, which is the honest answer: unknown,
            // and fillable on the phone.
            let actuals = MetricValues.fromRaw(stepResult.extraActuals)
            if !extras.isEmpty || !actuals.isEmpty {
                log.extraTargets = extras
                if stepResult.completedAt != nil, !actuals.isEmpty {
                    log.extraActuals = actuals
                }
                // The snapshot profile spans both sides: a measured
                // distance on an untargeted run must still be a tracked
                // metric, or the record cannot render what it holds.
                var metrics = Array(Set(extras.keys).union(actuals.keys))
                if stepResult.step.targetWeight != nil { metrics.append(.weight) }
                if stepResult.step.targetRepsLower != nil { metrics.append(.reps) }
                if stepResult.step.targetDuration != nil { metrics.append(.duration) }
                log.metricsData = MetricProfile(
                    metrics,
                    distanceUnit: stepResult.step.distanceUnit ?? .meters
                ).encoded()
            }
            log.restSecondsOverride = stepResult.step.restSecondsOverride
            log.session = session
            context.insert(log)
        }
        session.finish(at: result.endedAt)
        do {
            try context.save()
        } catch {
            Logger(subsystem: "com.davidcole.plusplus", category: "watch")
                .fault("wrist session save failed: \(error.localizedDescription)")
        }
    }

    /// Fills a live-mirror row from the wrist's authoritative summary.
    /// The result only ADDS what the ops could not carry — HR, measured
    /// extras, a completion the ops lost — and never downgrades a value
    /// the row already holds, so a re-delivered result is a no-op.
    private func merge(_ result: WatchSync.SessionResult, into session: WorkoutSession, context: ModelContext) {
        LiveMirror.clearRemoteActivity(session.sessionId)
        if result.averageHeartRate != nil { session.averageHeartRate = result.averageHeartRate }
        if result.maxHeartRate != nil { session.maxHeartRate = result.maxHeartRate }
        let logs = session.sortedSetLogs
        for (order, stepResult) in result.steps.enumerated() {
            guard let log = logs.first(where: { $0.order == order }) else { continue }
            if stepResult.averageHeartRate != nil { log.actualAverageHeartRate = stepResult.averageHeartRate }
            if stepResult.maxHeartRate != nil { log.actualMaxHeartRate = stepResult.maxHeartRate }
            guard let completedAt = stepResult.completedAt else { continue }
            if log.completedAt == nil {
                log.actualWeight = stepResult.actualWeight
                log.actualReps = stepResult.actualReps
                log.actualDuration = stepResult.actualDuration
                log.completedAt = completedAt
            }
            let actuals = MetricValues.fromRaw(stepResult.extraActuals)
            if !actuals.isEmpty, log.extraActuals.isEmpty {
                log.extraActuals = actuals
            }
            // The snapshot profile spans what the log now holds — same
            // rule as the fresh-import path above.
            let profile = log.metricProfile
            let newKeys = log.extraActuals.keys.filter { !profile.contains($0) }
            if !newKeys.isEmpty {
                log.metricsData = MetricProfile(
                    profile.metrics + newKeys, distanceUnit: profile.distanceUnit
                ).encoded()
            }
        }
        // The wrist's end is the honest one. The `.finished` op already
        // closed the row in the common case; correct the stamp when a
        // different door closed it first.
        if !session.isFinished {
            session.finish(at: result.endedAt)
        } else if let ended = session.endedAt, abs(ended.timeIntervalSince(result.endedAt)) > 1 {
            session.endedAt = result.endedAt
        }
        do {
            try context.save()
        } catch {
            Logger(subsystem: "com.davidcole.plusplus", category: "watch")
                .fault("wrist session merge failed: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate plumbing

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            pushPlan()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

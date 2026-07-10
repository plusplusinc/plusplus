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
                    steps.append(WatchSync.Step(
                        exerciseName: exercise.name,
                        groupIndex: groupIndex,
                        setNumber: setNumber,
                        isDuration: exercise.exerciseType == .duration,
                        targetWeight: entry.weight,
                        targetRepsLower: entry.reps,
                        targetRepsUpper: entry.repsUpper,
                        targetDuration: entry.durationSeconds,
                        targetHeartRateLowerBPM: heartBand?.lowerBound,
                        targetHeartRateUpperBPM: heartBand?.upperBound
                    ))
                }
            }
        }
        return WatchSync.PlanRoutine(name: routine.name, restSeconds: routine.restSeconds, steps: steps)
    }

    // MARK: - Receiving results

    /// IMPORTANT: WCSession marks the transfer delivered when this
    /// method RETURNS — anything deferred past that point can drop a
    /// once-delivered routine forever (bug hunt A4). So the import runs
    /// synchronously, on this queue, in a context created here (a
    /// ModelContext is usable on its creating thread).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
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

    /// Appends the wrist session as ordinary history. Idempotent:
    /// transferUserInfo retries across launches, so an already-imported
    /// (name, startedAt) pair is skipped.
    private func importResult(_ result: WatchSync.SessionResult, into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let alreadyImported = existing.contains {
            $0.routineName == result.routineName
                && abs($0.startedAt.timeIntervalSince(result.startedAt)) < 1
        }
        guard !alreadyImported else { return }

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

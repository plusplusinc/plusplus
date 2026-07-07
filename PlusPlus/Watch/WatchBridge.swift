import Foundation
import SwiftData
import WatchConnectivity
import PlusPlusKit

/// The phone side of watch sync (#6): pushes the workout plan whenever
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

    /// Encodes every workout in its execution order (the same superset
    /// rotation the phone's session factory produces) and ships it.
    func pushPlan() {
        guard let container, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        Task { @MainActor in
            let context = container.mainContext
            let workouts = (try? context.fetch(
                FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.order)])
            )) ?? []
            let plan = WatchSync.Plan(
                generatedAt: Date(),
                workouts: workouts.map(Self.planWorkout)
            )
            guard let data = try? WatchSync.encode(plan) else { return }
            try? session.updateApplicationContext(["plan": data])
        }
    }

    @MainActor
    private static func planWorkout(_ workout: Workout) -> WatchSync.PlanWorkout {
        var steps: [WatchSync.Step] = []
        for (groupIndex, group) in workout.sortedGroups.enumerated() {
            for setNumber in 1...max(group.sets, 1) {
                for entry in group.sortedExercises {
                    guard let exercise = entry.exercise else { continue }
                    steps.append(WatchSync.Step(
                        exerciseName: exercise.name,
                        groupIndex: groupIndex,
                        setNumber: setNumber,
                        isDuration: exercise.exerciseType == .duration,
                        targetWeight: entry.weight,
                        targetRepsLower: entry.reps,
                        targetRepsUpper: entry.repsUpper,
                        targetDuration: entry.durationSeconds
                    ))
                }
            }
        }
        return WatchSync.PlanWorkout(name: workout.name, restSeconds: workout.restSeconds, steps: steps)
    }

    // MARK: - Receiving results

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["sessionResult"] as? Data,
              let result = try? WatchSync.decode(WatchSync.SessionResult.self, from: data)
        else { return }
        Task { @MainActor in
            self.importResult(result)
        }
    }

    /// Appends the wrist session as ordinary history. Idempotent:
    /// transferUserInfo retries across launches, so an already-imported
    /// (name, startedAt) pair is skipped.
    @MainActor
    private func importResult(_ result: WatchSync.SessionResult) {
        guard let container else { return }
        let context = container.mainContext

        let existing = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let alreadyImported = existing.contains {
            $0.workoutName == result.workoutName
                && abs($0.startedAt.timeIntervalSince(result.startedAt)) < 1
        }
        guard !alreadyImported else { return }

        let session = WorkoutSession(
            workoutName: result.workoutName,
            startedAt: result.startedAt,
            restSeconds: result.restSeconds
        )
        context.insert(session)
        for (order, stepResult) in result.steps.enumerated() {
            let log = SetLog(
                order: order,
                groupIndex: stepResult.step.groupIndex,
                setNumber: stepResult.step.setNumber,
                exerciseName: stepResult.step.exerciseName,
                exerciseType: stepResult.step.isDuration ? .duration : .weightReps,
                targetWeight: stepResult.step.targetWeight,
                targetRepsLower: stepResult.step.targetRepsLower,
                targetRepsUpper: stepResult.step.targetRepsUpper,
                targetDuration: stepResult.step.targetDuration
            )
            log.actualWeight = stepResult.actualWeight
            log.actualReps = stepResult.actualReps
            log.actualDuration = stepResult.actualDuration
            log.completedAt = stepResult.completedAt
            log.session = session
            context.insert(log)
        }
        session.finish(at: result.endedAt)
        try? context.save()
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

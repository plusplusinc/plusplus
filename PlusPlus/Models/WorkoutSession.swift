import Foundation
import SwiftData
import PlusPlusKit

/// A performed (or in-progress) run of a workout. Snapshots what it needs
/// from the template at start time — later edits or deletion of the source
/// workout must never corrupt logged history.
@Model
final class WorkoutSession {
    var workout: Workout?
    var workoutName: String
    var startedAt: Date
    var endedAt: Date?
    /// Snapshot of the workout's rest setting at start time.
    var restSeconds: Int = 90
    /// Where the session is pointed (v2 jump/redo, #66): the order of the
    /// log the user is doing now. `currentLog` falls back to the first
    /// pending log when the cursor's log is already done.
    var cursorOrder: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var setLogs: [SetLog] = []

    init(workout: Workout? = nil, workoutName: String, startedAt: Date = Date(), restSeconds: Int = 90) {
        self.workout = workout
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.restSeconds = restSeconds
    }

    var sortedSetLogs: [SetLog] {
        setLogs.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var completedSetLogs: [SetLog] {
        sortedSetLogs.filter(\.isCompleted)
    }

    /// The set the user should do next; nil when everything is logged.
    var nextPendingLog: SetLog? {
        sortedSetLogs.first { !$0.isCompleted }
    }

    /// The cursor's log when it's still pending, else the first pending
    /// log (v2 jump/redo can move the cursor anywhere).
    var currentLog: SetLog? {
        sortedSetLogs.first { $0.order == cursorOrder && !$0.isCompleted } ?? nextPendingLog
    }

    /// Jump the session to a specific log ("Do now" / "Skip to"). With
    /// `redo`, a completed log is reopened first — its previous actuals
    /// stay as the prefill.
    func jump(to log: SetLog, redo: Bool = false) {
        if redo, log.isCompleted {
            log.completedAt = nil
        }
        guard !log.isCompleted else { return }
        cursorOrder = log.order
    }

    /// Marks the current log complete, prefilling actuals from targets,
    /// and carries a changed weight forward to the remaining pending sets
    /// of the same exercise (v2, #65). Advances the cursor to the next
    /// pending log after this one (wrapping to the first pending).
    func complete(_ log: SetLog, at date: Date = Date()) {
        if log.exerciseType == .duration {
            if log.actualDuration == nil { log.actualDuration = log.targetDuration }
        } else {
            if log.actualWeight == nil { log.actualWeight = log.targetWeight }
            if log.actualReps == nil { log.actualReps = log.targetRepsLower }
            if let newWeight = log.actualWeight, newWeight != log.targetWeight {
                for other in sortedSetLogs
                where !other.isCompleted && other !== log && other.exerciseName == log.exerciseName {
                    other.targetWeight = newWeight
                }
            }
        }
        log.completedAt = date
        let pending = sortedSetLogs.filter { !$0.isCompleted }
        cursorOrder = (pending.first { $0.order > log.order } ?? pending.first)?.order ?? cursorOrder
    }

    /// True when a different pending set of the same exercise will pick up
    /// this log's edited weight on completion — drives the carry-forward
    /// hint line.
    func weightCarriesForward(from log: SetLog) -> Bool {
        guard log.exerciseType != .duration,
              let actual = log.actualWeight, actual != log.targetWeight
        else { return false }
        return sortedSetLogs.contains { !$0.isCompleted && $0 !== log && $0.exerciseName == log.exerciseName }
    }

    var isFinished: Bool { endedAt != nil }

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    func finish(at date: Date = Date()) {
        endedAt = date
    }

    /// The most recent completed log for the same exercise as `log` from an
    /// earlier finished session — what "last time" looked like. Prefers the
    /// same set number within the newest session that included the exercise;
    /// falls back to that session's last set of the exercise. Matches by
    /// exercise identity when both references survive, else by name snapshot.
    static func lastPerformance(matching log: SetLog, in sessions: [WorkoutSession]) -> SetLog? {
        let priorSessions = sessions
            .filter { $0 !== log.session && $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }

        for session in priorSessions {
            let matches = session.completedSetLogs.filter { candidate in
                if let a = candidate.exercise, let b = log.exercise {
                    return a === b
                }
                return candidate.exerciseName == log.exerciseName
            }
            guard !matches.isEmpty else { continue }
            return matches.first { $0.setNumber == log.setNumber } ?? matches.last
        }
        return nil
    }

    /// Builds a session from a workout template with one SetLog per
    /// exercise per set, in execution order. Supersets rotate: a group with
    /// exercises [A, B] and 3 sets produces A1 B1 A2 B2 A3 B3.
    static func start(from workout: Workout, context: ModelContext, at date: Date = Date()) -> WorkoutSession {
        let session = WorkoutSession(
            workout: workout,
            workoutName: workout.name,
            startedAt: date,
            restSeconds: workout.restSeconds
        )
        context.insert(session)

        var order = 0
        for (groupIndex, group) in workout.sortedGroups.enumerated() {
            for setNumber in 1...max(group.sets, 1) {
                for workoutExercise in group.sortedExercises {
                    guard let exercise = workoutExercise.exercise else { continue }
                    let log = SetLog(
                        order: order,
                        groupIndex: groupIndex,
                        setNumber: setNumber,
                        exercise: exercise,
                        exerciseName: exercise.name,
                        exerciseType: exercise.exerciseType,
                        targetWeight: workoutExercise.weight,
                        targetRepsLower: workoutExercise.reps,
                        targetRepsUpper: workoutExercise.repsUpper,
                        targetDuration: workoutExercise.durationSeconds
                    )
                    log.session = session
                    context.insert(log)
                    order += 1
                }
            }
        }
        // Save NOW, not on the next autosave: the session is presented
        // via fullScreenCover(item:), which keys on persistentModelID —
        // the temporary→permanent ID swap at first save reads as a new
        // item and briefly dismisses/re-presents a live workout (Dave,
        // build 12).
        try? context.save()
        return session
    }
}

/// One planned/performed set of one exercise within a session. Targets are
/// copied from the plan; actuals are what happened. Exercise name and type
/// are snapshotted so history survives library edits.
@Model
final class SetLog {
    var session: WorkoutSession?
    var order: Int
    var groupIndex: Int
    /// 1-based set number within the group.
    var setNumber: Int
    var exercise: Exercise?
    var exerciseName: String
    var exerciseType: ExerciseType

    var targetWeight: Double?
    var targetRepsLower: Int?
    var targetRepsUpper: Int?
    var targetDuration: Int?

    var actualWeight: Double?
    var actualReps: Int?
    var actualDuration: Int?
    var completedAt: Date?

    init(
        order: Int,
        groupIndex: Int,
        setNumber: Int,
        exercise: Exercise? = nil,
        exerciseName: String,
        exerciseType: ExerciseType = .weightReps,
        targetWeight: Double? = nil,
        targetRepsLower: Int? = nil,
        targetRepsUpper: Int? = nil,
        targetDuration: Int? = nil
    ) {
        self.order = order
        self.groupIndex = groupIndex
        self.setNumber = setNumber
        self.exercise = exercise
        self.exerciseName = exerciseName
        self.exerciseType = exerciseType
        self.targetWeight = targetWeight
        self.targetRepsLower = targetRepsLower
        self.targetRepsUpper = targetRepsUpper
        self.targetDuration = targetDuration
    }

    var isCompleted: Bool { completedAt != nil }

    var targetReps: RepTarget {
        RepTarget(lower: targetRepsLower, upper: targetRepsUpper)
    }

    /// "10 reps @ 135 lb", "45 sec", "25:00", or "—" — how this set went.
    /// Weight numbers are unit-agnostic; the caller supplies the current
    /// unit setting (issue #33).
    func resultSummary(weightUnit: WeightUnit) -> String {
        if exerciseType == .duration {
            guard let seconds = actualDuration else { return "—" }
            return WorkoutMetric.duration.displayText(Double(seconds))
        }
        var parts: [String] = []
        if let reps = actualReps {
            parts.append("\(reps) reps")
        }
        if let weight = actualWeight, weight > 0 {
            parts.append("@ \(WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit))")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }
}

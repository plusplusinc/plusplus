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
    var resultSummary: String {
        if exerciseType == .duration {
            guard let seconds = actualDuration else { return "—" }
            return WorkoutMetric.duration.displayText(Double(seconds))
        }
        var parts: [String] = []
        if let reps = actualReps {
            parts.append("\(reps) reps")
        }
        if let weight = actualWeight, weight > 0 {
            parts.append("@ \(WorkoutMetric.weight.formatted(weight)) lb")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }
}

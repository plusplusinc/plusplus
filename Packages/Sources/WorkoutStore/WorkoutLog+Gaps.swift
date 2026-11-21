import Foundation

/// A muscle group's sets in the period, and when it was last worked.
public struct GroupRecency: Identifiable, Equatable, Sendable {
    public let group: MuscleGroup
    /// Days between the day of the newest workout with a set for it and today; nil for none.
    public let daysAgo: Int?
    /// Its sets in the period, a round done one side at a time counted once.
    public let sets: Int

    public var id: MuscleGroup {
        group
    }

    /// Not worked in the last 2 weeks.
    public var isMissed: Bool {
        (daysAgo ?? .max) >= WorkoutLog.missedDays
    }
}

/// An exercise in three or more workouts in the period, its top set the same in all.
public struct StuckExercise: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let exercise: Exercise?
    public let isPerSide: Bool
    public let topSet: TopSet
    /// The logged workouts it was in.
    public let loggedWorkouts: Int
}

/// What has been left alone: muscle groups not worked lately, and exercises not moving.
public struct Gaps: Equatable, Sendable {
    /// All six groups, fewest sets first, ties in declaration order.
    public let groups: [GroupRecency]
    public let notMoving: [StuckExercise]

    /// The most sets any group has, the length a group's bar is measured against; 0 for none.
    public var mostSets: Int {
        groups.map(\.sets).max() ?? 0
    }
}

extension WorkoutLog {
    /// A group unworked for this many days is listed.
    public static let missedDays = 14
    /// An exercise in this many logged workouts with one top set is not moving.
    public static let stuckLoggedWorkouts = 3

    /// Gaps at `now`. A set counts toward each group its exercise works now, through `list`: a
    /// created exercise toward every group it checks, and one that no longer resolves toward
    /// none.
    public func gaps(in list: ExerciseList, now: Date, calendar: Calendar) -> Gaps {
        let recent = inPeriod(now: now, calendar: calendar)
        let recentExercises = recent.flatMap { $0.loggedExercises(in: list) }
        let groups = MuscleGroup.allCases.enumerated().map { index, group in
            let newest = loggedWorkouts.first { loggedWorkout in
                loggedWorkout.sets.contains {
                    list.exercise(id: $0.exerciseID)?.muscleGroups.contains(group) ?? false
                }
            }
            let sets = recentExercises
                .filter { $0.exercise?.muscleGroups.contains(group) ?? false }
                .reduce(0) { $0 + $1.rounds.count }
            return (index, GroupRecency(
                group: group,
                daysAgo: newest.map { Self.daysAgo($0, now: now, calendar: calendar) },
                sets: sets,
            ))
        }
        .sorted { ($0.1.sets, $0.0) < ($1.1.sets, $1.0) }
        .map(\.1)
        let notMoving = history(of: recent, in: list)
            .filter { history in
                history.topSets.count >= Self.stuckLoggedWorkouts
                    && zip(history.topSets, history.topSets.dropFirst())
                    .allSatisfy { $1.change(from: $0) == .same }
            }
            .sorted { $0.lastDone > $1.lastDone }
            .map { history in
                StuckExercise(
                    id: history.id,
                    name: history.name,
                    exercise: history.exercise,
                    isPerSide: history.isPerSide,
                    topSet: history.topSets[history.topSets.count - 1],
                    loggedWorkouts: history.topSets.count,
                )
            }
        return Gaps(groups: groups, notMoving: notMoving)
    }
}

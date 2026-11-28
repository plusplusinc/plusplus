import Foundation

/// A muscle group's sets in the period, and when it was last worked.
public struct GroupRecency: Identifiable, Equatable, Sendable {
    public let group: MuscleGroup
    /// Days between the day the newest workout with a set for it started and today; nil for none.
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

/// How the work is spread: the muscle groups by their sets, and which were not worked lately.
public struct Balance: Equatable, Sendable {
    /// All six groups, fewest sets first, ties in declaration order.
    public let groups: [GroupRecency]

    /// The most sets any group has, the length a group's bar is measured against; 0 for none.
    public var mostSets: Int {
        groups.map(\.sets).max() ?? 0
    }
}

extension WorkoutLog {
    /// A group unworked for this many days is missed, drawn stressed.
    public static let missedDays = 14

    /// Balance at `now`. A set counts toward each group its exercise works now, through `list`: a
    /// created exercise toward every group it checks, and one that no longer resolves toward
    /// none.
    public func balance(in list: ExerciseList, now: Date, calendar: Calendar) -> Balance {
        let recent = inPeriod(now: now, calendar: calendar)
        let recentExercises = recent.flatMap { $0.loggedExercises(in: list) }
        let groups = MuscleGroup.allCases.enumerated().map { index, group in
            let newest = workoutSessions.first { workoutSession in
                workoutSession.sets.contains {
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
        return Balance(groups: groups)
    }
}

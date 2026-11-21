import Foundation

/// When a muscle group was last worked, and which of the last four weeks had a set for it.
public struct GroupRecency: Identifiable, Equatable, Sendable {
    public let group: MuscleGroup
    /// When the newest workout with a set for it finished; nil for none.
    public let lastWorked: Date?
    /// Days between that workout's day and today; nil for none.
    public let daysAgo: Int?
    /// The last four weeks, this one first, each 7 days back from today: whether it had a set.
    public let weeks: [Bool]

    public var id: MuscleGroup {
        group
    }

    /// Not worked in the last 2 weeks.
    public var isMissed: Bool {
        (daysAgo ?? .max) >= WorkoutLog.missedDays
    }
}

/// An exercise in three or more workouts in the last 4 weeks, its top set the same in all.
public struct StuckExercise: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let exercise: Exercise?
    public let isPerSide: Bool
    public let topSet: TopSet
    public let workouts: Int
}

/// What has been left alone: muscle groups not worked lately, and exercises not moving.
public struct Gaps: Equatable, Sendable {
    /// All six groups, in declaration order.
    public let groups: [GroupRecency]
    public let notMoving: [StuckExercise]

    /// The groups not worked in the last 2 weeks.
    public var notWorkedLately: [GroupRecency] {
        groups.filter(\.isMissed)
    }

    public var isEmpty: Bool {
        notWorkedLately.isEmpty && notMoving.isEmpty
    }
}

extension WorkoutLog {
    /// A group unworked for this many days is listed.
    public static let missedDays = 14
    /// An exercise in this many workouts with one top set is not moving.
    public static let stuckWorkouts = 3

    /// Gaps at `now`. A set counts toward each group its exercise works now, through `list`: a
    /// created exercise toward every group it checks, and one that no longer resolves toward
    /// none.
    public func gaps(in list: ExerciseList, now: Date, calendar: Calendar) -> Gaps {
        let groups = MuscleGroup.allCases.map { group in
            let worked = workouts.filter { workout in
                workout.sets.contains {
                    list.exercise(id: $0.exerciseID)?.muscleGroups.contains(group) ?? false
                }
            }
            let days = worked.map { Self.daysAgo($0, now: now, calendar: calendar) }
            let weeks = (0 ..< 4).map { week in
                days.contains { $0 >= week * 7 && $0 < (week + 1) * 7 }
            }
            return GroupRecency(
                group: group,
                lastWorked: worked.first?.endedAt,
                daysAgo: days.first,
                weeks: weeks,
            )
        }
        let recent = within(days: Self.progressDays, of: now, calendar: calendar)
        let notMoving = history(of: recent, in: list)
            .filter { history in
                history.topSets.count >= Self.stuckWorkouts
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
                    workouts: history.topSets.count,
                )
            }
        return Gaps(groups: groups, notMoving: notMoving)
    }
}

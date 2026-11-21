import Foundation

/// One round of an exercise as a workout did it: a set, or for an exercise done one side at a
/// time, its left and right, in the order logged.
public struct LoggedRound: Equatable, Sendable {
    public let round: Int
    public internal(set) var sides: [LoggedSet]

    /// The set the round counts as: its lesser side, fewer reps or the shorter time, since "per
    /// side" claims both sides did it; a round with one side logged counts as that side.
    public var counted: LoggedSet {
        sides.min { $0.target.amount < $1.target.amount } ?? sides[0]
    }

    /// The round's top set.
    public var topSet: TopSet {
        TopSet(target: counted.target, weight: counted.weight)
    }

    /// Whether a side was done short of its plan: fewer reps, or a count stopped before its time.
    public var isShort: Bool {
        sides.contains { $0.target.amount < $0.plannedLength }
    }
}

/// An exercise as one workout did it: its sets grouped into rounds, under the name it was
/// logged with.
public struct LoggedExercise: Identifiable, Equatable, Sendable {
    /// The exercise's `Exercise.id`.
    public let id: String
    /// The name it was logged with, else its name now (a set from before names were kept), else
    /// "Exercise".
    public let name: String
    /// The exercise as it is now, for its load; nil for one since deleted.
    public let exercise: Exercise?
    public let rounds: [LoggedRound]

    /// The heaviest round; among those at that weight, the most reps or the longest time.
    public var topSet: TopSet {
        rounds.map(\.topSet).max(by: TopSet.isBelow) ?? rounds[0].topSet
    }

    /// Whether its rounds are done one side at a time.
    public var isPerSide: Bool {
        rounds.contains { $0.sides.contains { $0.side != nil } }
    }
}

extension LoggedWorkout {
    /// Its sets grouped by exercise, in the order each exercise was first logged, so a superset's
    /// A1 B1 A2 B2 reads A then B, and one exercise in two rows reads once. A round is a row's
    /// round: an exercise in two rows keeps both rows' rounds, in the order logged.
    public func loggedExercises(in list: ExerciseList) -> [LoggedExercise] {
        var order: [String] = []
        var rounds: [String: [LoggedRound]] = [:]
        var roundIndex: [String: [PlannedRound: Int]] = [:]
        var names: [String: String] = [:]
        for set in sets {
            let id = set.exerciseID
            if rounds[id] == nil {
                order.append(id)
                rounds[id] = []
            }
            if let name = set.exerciseName {
                names[id] = name
            }
            let key = PlannedRound(row: set.row, round: set.round)
            if let index = roundIndex[id]?[key] {
                rounds[id]?[index].sides.append(set)
            } else {
                roundIndex[id, default: [:]][key] = rounds[id]?.count ?? 0
                rounds[id]?.append(LoggedRound(round: set.round, sides: [set]))
            }
        }
        return order.map { id in
            let exercise = list.exercise(id: id)
            return LoggedExercise(
                id: id,
                name: names[id] ?? exercise?.name ?? "Exercise",
                exercise: exercise,
                rounds: rounds[id] ?? [],
            )
        }
    }
}

private struct PlannedRound: Hashable {
    let row: RoutineExercise.ID
    let round: Int
}

extension LoggedSet {
    /// The reps or seconds planned, a timed set's +15 s taps included.
    var plannedLength: Int {
        plannedTarget.amount + (plannedTarget.isTime ? timeAdded : 0)
    }
}

extension SetTarget {
    /// The reps or seconds.
    var amount: Int {
        switch self {
        case let .reps(reps): reps
        case let .time(seconds): seconds
        }
    }

    var isTime: Bool {
        if case .time = self {
            true
        } else {
            false
        }
    }
}

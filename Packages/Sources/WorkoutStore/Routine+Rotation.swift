import Foundation

/// The side of the body a set of a per-side exercise works, each side its own set.
public enum Side: String, Sendable, CaseIterable {
    case left
    case right
}

/// One set of a routine as a workout will do it: a row's set in a round, from 1, and for an
/// exercise done one side at a time, the side.
public struct PlannedSet: Hashable, Sendable {
    public let row: RoutineExercise.ID
    public let round: Int
    /// Nil for an exercise not done per side.
    public let side: Side?

    public init(row: RoutineExercise.ID, round: Int, side: Side? = nil) {
        self.row = row
        self.round = round
        self.side = side
    }
}

extension Routine {
    /// Every set of the routine in the order a workout does them: a plain row's sets one after
    /// another, and a superset's a round at a time, one set of each member in order (A1 B1 A2
    /// B2). A per-side exercise's set goes left then right, each side its own set, the two
    /// together in its turn of a round (A1L A1R B1). A member whose sets run out, which only
    /// unequal stored counts would make, drops out of the later rounds.
    public var setOrder: [PlannedSet] {
        var order: [PlannedSet] = []
        var start = exercises.startIndex
        while start < exercises.endIndex {
            let run = supersetRun(at: start) ?? start ... start
            let members = exercises[run]
            let rounds = members.map(\.plan.sets).max() ?? 0
            for round in stride(from: 1, through: rounds, by: 1) {
                for member in members where member.plan.sets >= round {
                    for side in member.sides {
                        order.append(PlannedSet(row: member.id, round: round, side: side))
                    }
                }
            }
            start = run.upperBound + 1
        }
        return order
    }

    /// The set a workout does next, having logged `logged`: the first in `setOrder` not yet
    /// logged, or nil once every one is. One rule for a relaunch, a row added or deleted
    /// mid-workout, and a sets count lowered under what is logged.
    public func nextSet(after logged: [LoggedSet]) -> PlannedSet? {
        let done = Set(logged.map(\.planned))
        return setOrder.first { !done.contains($0) }
    }

    /// How many of the row's sets are done, a set counting once every side of it is, out of
    /// its planned sets: what its set bars show.
    public func progress(
        of row: RoutineExercise.ID,
        logged: [LoggedSet],
    ) -> (done: Int, total: Int) {
        guard let item = exercises.first(where: { $0.id == row }) else { return (0, 0) }
        let done = Set(logged.map(\.planned))
        let finished = stride(from: 1, through: item.plan.sets, by: 1).count { round in
            item.sides.allSatisfy { done.contains(PlannedSet(row: row, round: round, side: $0)) }
        }
        return (finished, item.plan.sets)
    }

    /// Whether any set, or side of one, of the row is logged.
    public func isStarted(_ row: RoutineExercise.ID, logged: [LoggedSet]) -> Bool {
        logged.contains { $0.row == row }
    }
}

extension RoutineExercise {
    /// The sides each of its sets is done on: left then right for an exercise done one side at a
    /// time, else one with no side.
    var sides: [Side?] {
        exercise.isPerSide ? Side.allCases : [nil]
    }
}

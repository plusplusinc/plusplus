import Foundation

/// One set of a routine as a workout will do it: a row's set in a round, from 1.
public struct PlannedSet: Equatable, Sendable {
    public let row: RoutineExercise.ID
    public let round: Int

    public init(row: RoutineExercise.ID, round: Int) {
        self.row = row
        self.round = round
    }
}

extension Routine {
    /// Every set of the routine in the order a workout does them: a plain row's sets one after
    /// another, and a superset's a round at a time, one set of each member in order (A1 B1 A2
    /// B2). A member whose sets run out, which only unequal stored counts would make, drops out
    /// of the later rounds.
    public var setOrder: [PlannedSet] {
        var order: [PlannedSet] = []
        var start = exercises.startIndex
        while start < exercises.endIndex {
            let run = supersetRun(at: start) ?? start ... start
            let members = exercises[run]
            let rounds = members.map(\.plan.sets).max() ?? 0
            for round in stride(from: 1, through: rounds, by: 1) {
                for member in members where member.plan.sets >= round {
                    order.append(PlannedSet(row: member.id, round: round))
                }
            }
            start = run.upperBound + 1
        }
        return order
    }
}

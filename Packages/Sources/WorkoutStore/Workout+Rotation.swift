import Foundation

/// The side of the body a set of a per-side exercise works, each side its own set.
public enum Side: String, Sendable, CaseIterable {
    case left
    case right
}

/// One set of a workout as doing it will reach it: a row's set in a round, from 1, and for an
/// exercise done one side at a time, the side.
public struct PlannedSet: Hashable, Sendable {
    public let row: WorkoutExercise.ID
    public let round: Int
    /// Nil for an exercise not done per side.
    public let side: Side?

    /// `side` has no default, so a set built for a per-side exercise never leaves it out and
    /// matches no planned set: pass nil only for an exercise not done per side.
    public init(row: WorkoutExercise.ID, round: Int, side: Side?) {
        self.row = row
        self.round = round
        self.side = side
    }
}

/// How far a row is through its sets, as its set bars show it (`Workout.progress(of:logged:)`).
public struct RowProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    /// For a row done one side at a time, the sides logged of its first set not yet done.
    public var sidesDone: Int?

    public init(done: Int = 0, total: Int = 0, sidesDone: Int? = nil) {
        self.done = done
        self.total = total
        self.sidesDone = sidesDone
    }

    /// As it stands once the set in progress is done, on every side.
    public var afterSet: Self {
        Self(done: done + 1, total: total, sidesDone: sidesDone.map { _ in 0 })
    }
}

extension Workout {
    /// Every set of the workout in the order they are done: a plain row's sets one after
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
        nextSet(notIn: Set(logged.map(\.planned)))
    }

    /// The first set in `setOrder` not in `done`.
    func nextSet(notIn done: Set<PlannedSet>) -> PlannedSet? {
        setOrder.first { !done.contains($0) }
    }

    /// What the key that logs `set` says, having logged `logged`: "Log last set" on the workout's
    /// last planned set, "Log left" or "Log right" on a side, and otherwise "Log set". Never the
    /// next exercise's name, which shows below.
    public func logText(for set: PlannedSet, after logged: [LoggedSet]) -> String {
        let done = Set(logged.map(\.planned)).union([set])
        guard setOrder.contains(where: { !done.contains($0) }) else {
            return String(localized: "Log last set")
        }
        return switch set.side {
        case .left: String(localized: "Log left")
        case .right: String(localized: "Log right")
        case nil: String(localized: "Log set")
        }
    }

    /// How many of the row's sets are done, a set counting once every side of it is, out of
    /// its planned sets: what its set bars show. For a row done one side at a time, `sidesDone`
    /// is how many sides are logged of its first set not yet done, 0 or 1, which splits that
    /// set's bar; nil for any other row.
    public func progress(
        of row: WorkoutExercise.ID,
        logged: [LoggedSet],
    ) -> RowProgress {
        guard let item = exercises.first(where: { $0.id == row }) else { return RowProgress() }
        let done = Set(logged.map(\.planned))
        let sidesIn = stride(from: 1, through: item.plan.sets, by: 1).map { round in
            item.sides.count { done.contains(PlannedSet(row: row, round: round, side: $0)) }
        }
        let sides = item.sides.count
        return RowProgress(
            done: sidesIn.count { $0 == sides },
            total: item.plan.sets,
            sidesDone: sides > 1 ? sidesIn.first { $0 < sides } ?? 0 : nil,
        )
    }

    /// Whether any set, or side of one, of the row is logged.
    public func isStarted(_ row: WorkoutExercise.ID, logged: [LoggedSet]) -> Bool {
        logged.contains { $0.row == row }
    }
}

extension WorkoutExercise {
    /// The sides each of its sets is done on: left then right for an exercise done one side at a
    /// time, else one with no side.
    var sides: [Side?] {
        exercise.isPerSide ? Side.allCases : [nil]
    }
}

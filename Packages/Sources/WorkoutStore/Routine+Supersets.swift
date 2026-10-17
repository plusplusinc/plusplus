import Foundation

// Supersets: rows next to each other that share a `supersetID`, done one round at a time. A
// superset is at least two rows long and in one piece, and its rows share one round count, their
// `plan.sets`, since rounds alternate. Every rule here keeps that true.

/// What a drag from one row's node to another's makes of the routine's supersets: a join, or a
/// part.
public struct Regrouping: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Every gap the drag spans joins: the held row and every row it passed are one superset.
        case join
        /// Every joined gap the drag spans opens, up to the end of the held row's superset.
        case part
    }

    public var routine: Routine
    public var kind: Kind

    /// The rows of the superset a join made, the held row's; none for a part.
    public var joined: [RoutineExercise.ID] {
        guard kind == .join else { return [] }
        return routine.exercises.filter { $0.supersetID == heldSuperset }.map(\.id)
    }

    fileprivate let heldSuperset: UUID?
}

extension Routine {
    /// The rows joined to the row after them, in a superset with it.
    public var joinedToNext: Set<RoutineExercise.ID> {
        Set(zip(exercises, exercises.dropFirst()).compactMap { row, next in
            row.supersetID != nil && row.supersetID == next.supersetID ? row.id : nil
        })
    }

    public func isInSuperset(_ id: RoutineExercise.ID) -> Bool {
        exercises.first { $0.id == id }?.supersetID != nil
    }

    /// The other rows in `id`'s superset, in order; none for a plain row.
    public func partners(of id: RoutineExercise.ID) -> [RoutineExercise] {
        guard let superset = exercises.first(where: { $0.id == id })?.supersetID else { return [] }
        return exercises.filter { $0.supersetID == superset && $0.id != id }
    }

    /// What holding `held`'s node and dragging it to `reach`'s would make, decided by the first
    /// gap the drag crosses, the one next to the held row: open, it is a join; joined, a part.
    ///
    /// A join joins every gap from the held row to `reach`, and any superset it touches comes
    /// along whole, so supersets merge; every row takes the held row's round count. A part opens
    /// every joined gap from the held row to `reach`, stopping at the end of the held row's
    /// superset, and leaves round counts as they were. Nil when either row is missing or they
    /// are the same row.
    public func regrouped(
        holding held: RoutineExercise.ID,
        reaching reach: RoutineExercise.ID,
    ) -> Regrouping? {
        guard let from = exercises.firstIndex(where: { $0.id == held }),
              let to = exercises.firstIndex(where: { $0.id == reach }), from != to
        else { return nil }
        let step = to > from ? 1 : -1
        var rows = exercises
        let kind: Regrouping.Kind
        if isJoined(from, from + step) {
            kind = .part
            var gap = from
            while gap != to, isJoined(gap, gap + step) {
                // Everything past this gap, in the held row's superset, goes on as its own.
                let split = UUID()
                var row = gap + step
                while exercises.indices.contains(row), isJoined(row - step, row) {
                    rows[row].supersetID = split
                    row += step
                }
                gap += step
            }
        } else {
            kind = .join
            var first = min(from, to)
            var last = max(from, to)
            while first > 0, isJoined(first - 1, first) {
                first -= 1
            }
            while last < exercises.count - 1, isJoined(last, last + 1) {
                last += 1
            }
            let superset = exercises[from].supersetID
                ?? exercises[first ... last].lazy.compactMap(\.supersetID).first
                ?? UUID()
            let rounds = exercises[from].plan.sets
            for row in first ... last {
                rows[row].supersetID = superset
                rows[row].plan.sets = rounds
            }
        }
        rows.normalizeSupersets()
        var routine = self
        routine.exercises = rows
        return Regrouping(routine: routine, kind: kind, heldSuperset: rows[from].supersetID)
    }

    /// Applies `regrouped(holding:reaching:)`. Returns false when it changes nothing.
    @discardableResult
    public mutating func regroup(
        holding held: RoutineExercise.ID,
        reaching reach: RoutineExercise.ID,
    ) -> Bool {
        guard let regrouping = regrouped(holding: held, reaching: reach) else { return false }
        self = regrouping.routine
        return true
    }

    /// Removes the row `id`; a superset left with one row leaves it plain.
    public mutating func remove(_ id: RoutineExercise.ID) {
        exercises.removeAll { $0.id == id }
        exercises.normalizeSupersets()
    }

    /// Writes `row` back over the row with its id. A changed round count in a superset changes
    /// every member's, since they share it.
    public mutating func update(_ row: RoutineExercise) {
        guard let index = exercises.firstIndex(where: { $0.id == row.id }) else { return }
        let old = exercises[index]
        exercises[index] = row
        guard let superset = row.supersetID, row.plan.sets != old.plan.sets else { return }
        for other in exercises.indices where exercises[other].supersetID == superset {
            exercises[other].plan.sets = row.plan.sets
        }
    }

    /// Whether `id` and its neighbor on `side` could be joined: there is one, and they aren't in
    /// one superset yet.
    public func canJoin(_ id: RoutineExercise.ID, _ side: RoutineNeighbor) -> Bool {
        neighbor(of: id, side).map { !isJoined($0.index, $0.other) } ?? false
    }

    /// Joins `id` with its neighbor on `side`, as a drag of its node onto the neighbor's would.
    public mutating func join(_ id: RoutineExercise.ID, _ side: RoutineNeighbor) {
        guard canJoin(id, side), let pair = neighbor(of: id, side) else { return }
        regroup(holding: id, reaching: exercises[pair.other].id)
    }

    /// Takes `id` out of its superset as a plain row: in place at either end of it, and from the
    /// middle, to just below it, the rest staying joined.
    public mutating func leaveSuperset(_ id: RoutineExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              let run = supersetRun(at: index)
        else { return }
        if index == run.lowerBound || index == run.upperBound {
            exercises[index].supersetID = nil
            exercises.normalizeSupersets()
        } else {
            move(id, to: slot(after: run.upperBound))
        }
    }

    /// The indices of the superset the row at `index` is in, or nil for a plain row.
    func supersetRun(at index: Int) -> ClosedRange<Int>? {
        guard exercises[index].supersetID != nil else { return nil }
        var first = index
        var last = index
        while first > 0, isJoined(first - 1, first) {
            first -= 1
        }
        while last < exercises.count - 1, isJoined(last, last + 1) {
            last += 1
        }
        return first ... last
    }

    /// Whether the rows at two indices, next to each other, are in one superset. False when
    /// either is out of range.
    private func isJoined(_ first: Int, _ second: Int) -> Bool {
        guard exercises.indices.contains(first), exercises.indices.contains(second),
              let superset = exercises[first].supersetID
        else { return false }
        return exercises[second].supersetID == superset
    }

    private func neighbor(
        of id: RoutineExercise.ID,
        _ side: RoutineNeighbor,
    ) -> (index: Int, other: Int)? {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return nil }
        let other = side == .above ? index - 1 : index + 1
        return exercises.indices.contains(other) ? (index, other) : nil
    }
}

extension [RoutineExercise] {
    /// Restores what every superset holds to: in one piece, so a second run of an id gets an id
    /// of its own; at least two rows, so a run of one goes plain; and one round count, its first
    /// row's.
    mutating func normalizeSupersets() {
        var seen = Set<UUID>()
        var start = startIndex
        while start < endIndex {
            guard let superset = self[start].supersetID else {
                start += 1
                continue
            }
            var end = start + 1
            while end < endIndex, self[end].supersetID == superset {
                end += 1
            }
            if end - start == 1 {
                self[start].supersetID = nil
            } else {
                let kept = seen.contains(superset) ? UUID() : superset
                seen.insert(kept)
                let rounds = self[start].plan.sets
                for row in start ..< end {
                    self[row].supersetID = kept
                    self[row].plan.sets = rounds
                }
            }
            start = end
        }
    }
}

import Foundation

/// Where a moved row lands in its routine. A slot names a row by id, not an index, so it still
/// means the same place if the rows change under it.
public struct RoutineSlot: Hashable, Sendable {
    public enum Place: Hashable, Sendable {
        /// Just above this row.
        case before(RoutineExercise.ID)
        /// After the last row.
        case end
    }

    public var place: Place
    /// The neighbor whose superset the row joins there, or nil to land plain; a plain neighbor
    /// pairs with the row in a new superset. Between two rows of one superset a row always joins
    /// it, since no plain row sits inside one.
    public var joining: RoutineNeighbor?

    public init(_ place: Place, joining: RoutineNeighbor? = nil) {
        self.place = place
        self.joining = joining
    }

    /// Just above `id`.
    public static func before(_ id: RoutineExercise.ID, joining: RoutineNeighbor? = nil) -> Self {
        Self(.before(id), joining: joining)
    }

    /// After the last row.
    public static let end = Self(.end)
}

/// The row next to a slot or a row: the one above it, or below.
public enum RoutineNeighbor: Hashable, Sendable {
    case above
    case below
}

extension Routine {
    /// Moves the row `id` to `slot`, into the superset the slot joins, a new one with the plain
    /// row it joins, or out as a plain row. A row that joins a superset takes its round count; a
    /// new pair takes the larger of the two rows' set counts, so pairing never cuts a row's sets.
    /// Returns false, and changes nothing, when the row or the row the slot names is missing, or
    /// when the
    /// slot is the row's own place in its own superset, or none.
    @discardableResult
    public mutating func move(_ id: RoutineExercise.ID, to slot: RoutineSlot) -> Bool {
        guard let from = exercises.firstIndex(where: { $0.id == id }) else { return false }
        var rest = exercises
        var row = rest.remove(at: from)
        let to: Int
        switch slot.place {
        case let .before(target):
            guard target != id, let index = rest.firstIndex(where: { $0.id == target })
            else { return false }
            to = index
        case .end:
            to = rest.endIndex
        }
        let above = to > rest.startIndex ? rest[to - 1] : nil
        let below = to < rest.endIndex ? rest[to] : nil
        let joined: RoutineExercise? = switch slot.joining {
        case .above: above
        case .below: below
        case nil: above?.supersetID != nil && above?.supersetID == below?.supersetID ? above : nil
        }
        // Joining a plain row pairs the two in a new superset.
        let index = joined.flatMap { rest.firstIndex(of: $0) }
        if let index, rest[index].supersetID == nil {
            rest[index].supersetID = UUID()
            rest[index].plan.sets = max(rest[index].plan.sets, row.plan.sets)
        }
        let partner = index.map { rest[$0] }
        row.supersetID = partner?.supersetID
        if let partner, partner.supersetID != nil {
            row.plan.sets = partner.plan.sets
        }
        rest.insert(row, at: to)
        rest.normalizeSupersets()
        guard rest != exercises else { return false }
        exercises = rest
        return true
    }

    /// The slot one row up from `id`'s, or nil when there is none. A row in a superset moves only
    /// among its members, so it is nil at the superset's top; a plain row moves past a whole
    /// superset above it, staying plain.
    public func slotMovingUp(_ id: RoutineExercise.ID) -> RoutineSlot? {
        guard let index = exercises.firstIndex(where: { $0.id == id }), index > 0
        else { return nil }
        if let run = supersetRun(at: index) {
            return index > run.lowerBound ? .before(exercises[index - 1].id, joining: .below) : nil
        }
        let passed = supersetRun(at: index - 1)?.lowerBound ?? index - 1
        return .before(exercises[passed].id)
    }

    /// The slot one row down from `id`'s, or nil when there is none: as `slotMovingUp`, the other
    /// way.
    public func slotMovingDown(_ id: RoutineExercise.ID) -> RoutineSlot? {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              index < exercises.count - 1
        else { return nil }
        if let run = supersetRun(at: index) {
            return index < run.upperBound ? slot(after: index + 1, joining: .above) : nil
        }
        return slot(after: supersetRun(at: index + 1)?.upperBound ?? index + 1)
    }

    /// What VoiceOver says once `id` has moved one row up or down: the name of the row it passed,
    /// now just below it after a move up and just above it after a move down. Nil when there is
    /// no such row.
    public func moveAnnouncement(for id: RoutineExercise.ID, wentUp: Bool) -> String? {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return nil }
        let passed = wentUp ? index + 1 : index - 1
        guard exercises.indices.contains(passed) else { return nil }
        let name = exercises[passed].exercise.name
        return wentUp ? "Moved above \(name)" : "Moved below \(name)"
    }

    /// The slot just after the row at `index`.
    func slot(after index: Int, joining: RoutineNeighbor? = nil) -> RoutineSlot {
        index + 1 < exercises.count
            ? .before(exercises[index + 1].id, joining: joining)
            : RoutineSlot(.end, joining: joining)
    }
}

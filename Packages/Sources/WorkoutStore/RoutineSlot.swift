import Foundation

/// Where a moved row lands in its routine. A slot names a row by id, not an index, so it still
/// means the same place if the rows change under it.
public enum RoutineSlot: Hashable, Sendable {
    /// Just above this row.
    case before(RoutineExercise.ID)
    /// After the last row.
    case end
}

extension Routine {
    /// Moves the row `id` to `slot`. Returns false, and changes nothing, when the row or the
    /// row the slot names is missing, or when the slot is the row's own place.
    @discardableResult
    public mutating func move(_ id: RoutineExercise.ID, to slot: RoutineSlot) -> Bool {
        guard let from = exercises.firstIndex(where: { $0.id == id }) else { return false }
        var rest = exercises
        let row = rest.remove(at: from)
        let to: Int
        switch slot {
        case let .before(target):
            guard target != id, let index = rest.firstIndex(where: { $0.id == target })
            else { return false }
            to = index
        case .end:
            to = rest.endIndex
        }
        guard to != from else { return false }
        rest.insert(row, at: to)
        exercises = rest
        return true
    }

    /// The slot one row up from `id`'s, or nil when it is first, alone, or missing.
    public func slotMovingUp(_ id: RoutineExercise.ID) -> RoutineSlot? {
        guard let index = exercises.firstIndex(where: { $0.id == id }), index > 0
        else { return nil }
        return .before(exercises[index - 1].id)
    }

    /// The slot one row down from `id`'s, or nil when it is last, alone, or missing.
    public func slotMovingDown(_ id: RoutineExercise.ID) -> RoutineSlot? {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              index < exercises.count - 1
        else { return nil }
        let twoDown = index + 2
        return twoDown < exercises.count ? .before(exercises[twoDown].id) : .end
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
}

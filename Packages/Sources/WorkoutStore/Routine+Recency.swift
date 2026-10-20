import Foundation


extension [Routine] {
    /// The saved routines, latest first, with the open one as it is now in their place at the
    /// top: the open routine was launched, opened, or edited last, so it is the most recent,
    /// even while its last save is still on its way. An empty one is left out, as it is never
    /// stored.
    public func withOpen(_ open: Routine) -> [Routine] {
        let rest = filter { $0.id != open.id }
        return open.isEmpty ? rest : [open] + rest
    }

    /// The routines as they are now, in an order taken earlier, so a list doesn't reorder in
    /// view; one not in it yet goes first.
    public func held(in order: [Routine.ID]) -> [Routine] {
        let place = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return enumerated()
            // A routine not in the order keeps its place among the new, all before the rest.
            .sorted { (place[$0.element.id] ?? $0.offset - count)
                < (place[$1.element.id] ?? $1.offset - count)
            }
            .map(\.element)
    }

    /// The first `count`, these being latest first, put in the order they were last edited,
    /// latest first, so opening one never moves it and editing one does. One never edited, or
    /// edited at the same moment as another, keeps its place in this order.
    public func lastEdited(
        first count: Int,
        editedAt: [Routine.ID: Date],
    ) -> [Routine] {
        prefix(count).enumerated()
            .sorted { lhs, rhs in
                let left = editedAt[lhs.element.id] ?? .distantPast
                let right = editedAt[rhs.element.id] ?? .distantPast
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }
}

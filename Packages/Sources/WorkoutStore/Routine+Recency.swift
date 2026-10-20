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
            .sorted { (place[$0.element.id] ?? $0.offset - order.count)
                < (place[$1.element.id] ?? $1.offset - order.count)
            }
            .map(\.element)
    }
}

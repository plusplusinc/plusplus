extension [Routine] {
    /// The saved routines, latest first, with the open one as it is now in their place at the
    /// top: the open routine was launched, opened, or edited last, so it is the most recent,
    /// even while its last save is still on its way. An empty one is left out, as it is never
    /// stored.
    public func withOpen(_ open: Routine) -> [Routine] {
        let rest = filter { $0.id != open.id }
        return open.isEmpty ? rest : [open] + rest
    }
}

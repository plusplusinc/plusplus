extension WorkoutPhase {
    /// The workout End took from the store, while the list still draws it.
    public var drawnWorkout: Workout? {
        guard case let .ending(ending) = self, ending.drawsWorkout else { return nil }
        return ending.workout
    }

    /// The list leaves the workout End took from the store: it shrinks, or crossfades, out of it.
    @discardableResult
    public mutating func listLeaves() -> Bool {
        guard case var .ending(ending) = self, ending.drawsWorkout else { return false }
        ending.drawsWorkout = false
        self = .ending(ending)
        return true
    }
}

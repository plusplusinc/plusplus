import Foundation

extension WorkoutPhase {
    /// The workout End took from the store, while the list still draws it.
    public var drawnWorkout: LoggedWorkout? {
        guard case let .ending(ending) = self, ending.drawsWorkout else { return nil }
        return ending.workout
    }

    /// When End came, while the list still draws the workout it took: the rest drawn holds where
    /// it stood then.
    public var drawnEnd: Date? {
        guard case let .ending(ending) = self, ending.drawsWorkout else { return nil }
        return ending.date
    }

    /// The rest the screen draws: the one under way, or the one End came in, while the list still
    /// draws the workout, so End shrinks the list from the rest as drawn. Dropped at End, the
    /// rest went on the frame and the next exercise stood grown before it shrank.
    public var drawnRest: Resting? {
        if let resting {
            return resting
        }
        guard case let .ending(ending) = self, ending.drawsWorkout else { return nil }
        return ending.rest
    }

    /// The rest End came in, with the workout as it was, once the list has left it: its room
    /// closes showing the time it had. Gone with the list, its room closed drawing an empty rest,
    /// "0:00".
    public var restLeft: (rest: Resting, workout: LoggedWorkout)? {
        guard case let .ending(ending) = self, !ending.drawsWorkout, let rest = ending.rest
        else { return nil }
        return (rest, ending.workout)
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

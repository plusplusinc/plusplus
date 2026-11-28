import Foundation

extension WorkoutPhase {
    /// Whether an ending has begun and holds with the key still up, as under a finish's "++".
    public var isEndBegun: Bool {
        guard case let .ending(ending) = self else { return false }
        return ending.beat == .began
    }

    /// The workout session End took from the store, while the list still draws it.
    public var drawnWorkoutSession: WorkoutSession? {
        guard case let .ending(ending) = self, ending.drawsLiveWorkout else { return nil }
        return ending.workoutSession
    }

    /// When End came, while the list still draws the workout it took: the rest drawn holds where
    /// it stood then.
    public var drawnEnd: Date? {
        guard case let .ending(ending) = self, ending.drawsLiveWorkout else { return nil }
        return ending.date
    }

    /// The moment a drawn clock reads: End's while the list still draws the workout it took,
    /// so a count holds where End found it; else now. Read at each redraw instead, a count
    /// ticked on under a finish's "++".
    public var drawnMoment: Date {
        drawnEnd ?? .now
    }

    /// The rest the screen draws: the one under way, or the one End came in, while the list still
    /// draws the workout, so End shrinks the list from the rest as drawn. Dropped at End, the
    /// rest went on the frame and the next exercise stood grown before it shrank.
    public var drawnRest: Resting? {
        if let resting {
            return resting
        }
        guard case let .ending(ending) = self, ending.drawsLiveWorkout else { return nil }
        return ending.rest
    }

    /// The rest End came in, with the workout as it was, once the list has left it: its room
    /// closes showing the time it had. Gone with the list, its room closed drawing an empty rest,
    /// "0:00".
    public var restLeft: (rest: Resting, workoutSession: WorkoutSession)? {
        guard case let .ending(ending) = self, !ending.drawsLiveWorkout, let rest = ending.rest
        else { return nil }
        return (rest, ending.workoutSession)
    }

    /// The list leaves the workout End took from the store: it shrinks, or crossfades, out of it.
    @discardableResult
    public mutating func listLeaves() -> Bool {
        guard case var .ending(ending) = self, ending.drawsLiveWorkout else { return false }
        ending.drawsLiveWorkout = false
        self = .ending(ending)
        return true
    }
}

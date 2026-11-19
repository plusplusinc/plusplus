extension WorkoutPhase {
    /// A rest after a set, from the log until it ends: between exercises, or between two sets of
    /// one (`isWithinExercise`), where the rest takes the place of the set's numbers.
    public struct Resting: Equatable, Sendable {
        /// The set logged.
        public let set: PlannedSet
        public let isBack: Bool
        public let startsRound: Bool
        public let isWithinExercise: Bool
        public internal(set) var beat: Beat

        public enum Beat: Comparable, Sendable {
            /// Logged, and not yet drawn.
            case logged
            /// Drawn: the row left closing and the rest opening under it, or, within one
            /// exercise, the rest and the next set swapping places.
            case shown
            /// Between exercises, the pulse has landed at the rest, where the dot waits.
            case landed
            /// The change is over: nothing moves but the countdown and the dot.
            case settled
            /// Within one exercise, the rest over: the next set swapping back into the
            /// numbers' place.
            case returning
        }
    }

    /// Within one exercise, the swap back is over: the next set is up.
    @discardableResult
    public mutating func settleReturn() -> Bool {
        guard case let .resting(rest) = self, rest.beat == .returning else { return false }
        self = .running
        return true
    }

    /// Between exercises, the move into the rest has landed: the dot waits at the rest.
    @discardableResult
    public mutating func landRest() -> Bool {
        guard case var .resting(rest) = self, !rest.isWithinExercise, rest.beat == .shown
        else { return false }
        rest.beat = .landed
        self = .resting(rest)
        return true
    }

    /// A rest's opening is over: the row left has closed.
    @discardableResult
    public mutating func settleRest() -> Bool {
        guard case var .resting(rest) = self, rest.beat == .shown || rest.beat == .landed
        else { return false }
        rest.beat = .settled
        self = .resting(rest)
        return true
    }

    /// A rest is over: the move to the next exercise plays from the rest as a move with no rest
    /// does from its log, or with no motion (`moves`), fades on. Only once the rest is drawn and,
    /// between exercises, the move into it over.
    @discardableResult
    public mutating func endRest(moves: Bool = true) -> Bool {
        guard case var .resting(rest) = self, rest.beat < .returning,
              rest.beat >= (rest.isWithinExercise ? .shown : .settled)
        else { return false }
        guard !rest.isWithinExercise else {
            rest.beat = .returning
            self = .resting(rest)
            return true
        }
        guard moves else {
            self = .fadingOn(rest.set, isShown: false)
            return true
        }
        self = .movingOn(Move(
            set: rest.set,
            isBack: rest.isBack,
            startsRound: rest.startsRound,
            beat: .shown,
        ))
        return true
    }

    /// From Start's press until the first exercise has grown: the key is Start's.
    public var isStarting: Bool {
        self == .starting(.pressed) || self == .starting(.growing)
    }

    /// The set logged that stays on its exercise, shown as still to do until the line rolls on.
    public var held: PlannedSet? {
        guard case let .held(set) = self else { return nil }
        return set
    }

    /// As a workout ends, it as it was, until its time has faded: the time key's glass stays in
    /// the bar while the time fades out of it.
    public var endingWorkout: Workout? {
        guard case let .ending(ending) = self, ending.beat < .timeGone else { return nil }
        return ending.workout
    }

    /// The rest under way, if one is.
    public var resting: Resting? {
        guard case let .resting(rest) = self else { return nil }
        return rest
    }

    /// The move to another exercise under way, if one is.
    public var move: Move? {
        guard case let .movingOn(move) = self else { return nil }
        return move
    }

    /// The set whose words the key keeps while the workout moves on from it: a move's until the
    /// next row rolls on, a close's and a fade's until they are over, so the key changes with the
    /// row, not before it.
    public var keySet: PlannedSet? {
        switch self {
        case let .movingOn(move) where !move.hasRolled: move.set
        case let .closing(set, _), let .fadingOn(set, _): set
        default: nil
        }
    }
}

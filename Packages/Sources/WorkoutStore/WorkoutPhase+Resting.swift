extension WorkoutPhase {
    /// A rest between exercises, from the log until it ends.
    public struct Resting: Equatable, Sendable {
        /// The set logged.
        public let set: PlannedSet
        public let isBack: Bool
        public let startsRound: Bool
        public internal(set) var beat: Beat

        public enum Beat: Comparable, Sendable {
            /// Logged, and not yet drawn.
            case logged
            /// Drawn: the row left closing, the rest opening under it.
            case shown
            /// The close is over: nothing moves but the countdown and the dot.
            case settled
        }
    }

    /// A rest's opening is over: the row left has closed.
    @discardableResult
    public mutating func settleRest() -> Bool {
        guard case var .resting(rest) = self, rest.beat == .shown else { return false }
        rest.beat = .settled
        self = .resting(rest)
        return true
    }

    /// A rest is over: the move to the next exercise goes on from its landing, as if a pulse had
    /// just landed on the next row's node. Only once the rest is drawn.
    @discardableResult
    public mutating func endRest() -> Bool {
        guard case let .resting(rest) = self, rest.beat >= .shown else { return false }
        self = .movingOn(Move(
            set: rest.set,
            isBack: rest.isBack,
            startsRound: rest.startsRound,
            beat: .landed,
            isAfterRest: true,
        ))
        return true
    }

    /// The rest between exercises under way, if one is.
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

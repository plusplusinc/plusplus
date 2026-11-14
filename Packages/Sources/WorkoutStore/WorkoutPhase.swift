import Foundation

/// Where a workout on the routine screen is in its sequence: out of a workout, at rest, or
/// showing a set just logged, which stays on its exercise, moves on to another, or closes the
/// workout's last. A log is stored at once; the phase says what the screen still has to show of
/// it, so the screen draws the workout without it until its motion shows it.
///
/// Each transition changes the phase only from the phase it belongs to, and otherwise does
/// nothing and returns false: a beat that comes out of turn, or after its sequence was stopped,
/// changes nothing.
public enum WorkoutPhase: Equatable, Sendable {
    /// No workout.
    case idle
    /// A workout, at rest: the key takes a log.
    case running
    /// A set logged that stays on its exercise, not yet shown: the line rolls on after a beat.
    case held(PlannedSet)
    /// A set logged that moves the workout on to another exercise, with the pulse's motion.
    case movingOn(Move)
    /// The workout's last planned set, logged: its row closes. `isShown` once its motion has
    /// shown it.
    case closing(PlannedSet, isShown: Bool)
    /// With no motion, a set logged that moves the workout on, or past its last set, in one
    /// fade. `isShown` once the fade has shown it.
    case fadingOn(PlannedSet, isShown: Bool)

    /// A move from one exercise to another, from the log until the next has grown and its parts
    /// have come in.
    public struct Move: Equatable, Sendable {
        /// The set logged, and the next exercise's set it leads to.
        public let set: PlannedSet
        public let next: PlannedSet
        /// Whether the next row is above the one left: round a superset's loop, or to a row moved
        /// above.
        public let isBack: Bool
        /// Whether the move goes back to a superset's member in a later round, whose first member
        /// shows the round just done until the move rolls it on.
        public let startsRound: Bool
        public fileprivate(set) var beat: Beat

        /// A move's beats, in order.
        public enum Beat: Comparable, Sendable {
            /// Logged, and not yet drawn.
            case logged
            /// Drawn: its motion is under way.
            case shown
            /// The pulse has landed on the next row's node, which lights.
            case landed
            /// The next row shows its own set, rolled on from the round just done.
            case rolled
        }

        /// Whether the pulse has landed on the next row's node.
        public var isLanded: Bool {
            beat >= .landed
        }

        /// Whether the next row shows its own set: until then, the key keeps the set logged's
        /// words.
        public var hasRolled: Bool {
            beat == .rolled
        }

        /// Whether the next row still shows the round just done, rather than its own.
        public var holdsRound: Bool {
            startsRound && !hasRolled
        }
    }

    /// A screen opening: at rest in a workout, or out of one.
    public init(hasWorkout: Bool) {
        self = hasWorkout ? .running : .idle
    }

    // MARK: Transitions

    /// `set` was logged and stored, leading to `step`. Only at rest. `moves`: whether the screen
    /// plays motion; with none, a step to another exercise, or past the last set, is one fade.
    @discardableResult
    public mutating func log(
        _ set: PlannedSet,
        leadingTo step: LiveWorkout.Step,
        moves: Bool,
    ) -> Bool {
        guard self == .running else { return false }
        switch step {
        case .nextSet:
            self = .held(set)
        case let .nextExercise(next, isBack, startsRound) where moves:
            self = .movingOn(Move(
                set: set,
                next: next,
                isBack: isBack,
                startsRound: startsRound,
                beat: .logged,
            ))
        case .last where moves:
            self = .closing(set, isShown: false)
        case .nextExercise, .last:
            self = .fadingOn(set, isShown: false)
        }
        return true
    }

    /// The set logged is drawn: called inside the transaction that shows it. A held set's
    /// sequence is over once it shows.
    @discardableResult
    public mutating func show() -> Bool {
        switch self {
        case .held:
            self = .running
        case var .movingOn(move) where move.beat == .logged:
            move.beat = .shown
            self = .movingOn(move)
        case let .closing(set, false):
            self = .closing(set, isShown: true)
        case let .fadingOn(set, false):
            self = .fadingOn(set, isShown: true)
        default:
            return false
        }
        return true
    }

    /// A move's pulse lands on the next row's node.
    @discardableResult
    public mutating func land() -> Bool {
        advance(from: .shown, to: .landed)
    }

    /// A move's next row rolls on to its own set.
    @discardableResult
    public mutating func roll() -> Bool {
        advance(from: .landed, to: .rolled)
    }

    /// A move, a close, or a fade is over: back at rest.
    @discardableResult
    public mutating func settle() -> Bool {
        switch self {
        case let .movingOn(move) where move.hasRolled:
            self = .running
        case .closing(_, true), .fadingOn(_, true):
            self = .running
        default:
            return false
        }
        return true
    }

    /// Where the sequence playing was going, at once: as the screen goes away.
    public mutating func settleAtOnce() {
        if self != .idle {
            self = .running
        }
    }

    private mutating func advance(from beat: Move.Beat, to next: Move.Beat) -> Bool {
        guard case var .movingOn(move) = self, move.beat == beat else { return false }
        move.beat = next
        self = .movingOn(move)
        return true
    }

    // MARK: What the screen reads

    /// The sets logged and stored but not yet drawn: the screen draws the workout without them.
    public var hidden: [PlannedSet] {
        switch self {
        case let .held(set): [set]
        case let .movingOn(move) where move.beat == .logged: [move.set]
        case let .closing(set, false), let .fadingOn(set, false): [set]
        default: []
        }
    }

    /// The set logged that stays on its exercise, shown as still to do until the line rolls on.
    public var held: PlannedSet? {
        guard case let .held(set) = self else { return nil }
        return set
    }

    /// Whether the workout moves on from a set logged: to another exercise, or past its last.
    public var isMovingOn: Bool {
        switch self {
        case .movingOn, .closing, .fadingOn: true
        case .idle, .running, .held: false
        }
    }

    /// Whether the key takes a log: only at rest. While a set is held, a second tap in its beat,
    /// as a double tap would be, is dropped; while the workout moves on, the stored workout is
    /// already past the set drawn as current, and a log taken then would land on a set, or an
    /// exercise, not yet shown.
    public var takesLog: Bool {
        self == .running
    }

    /// Whether the last set's row is closing, the list's end held where it shows.
    public var isClosing: Bool {
        guard case .closing = self else { return false }
        return true
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

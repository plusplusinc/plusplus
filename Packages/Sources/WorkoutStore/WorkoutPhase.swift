import Foundation

/// Where a workout on the routine screen is in its sequence: out of a workout, starting, at rest,
/// showing a set just logged, which stays on its exercise, moves on to another, or closes the
/// workout's last, or ending. A log is stored at once; the phase says what the screen still has
/// to show of it, so the screen draws the workout without it until its motion shows it. End
/// takes over from any phase with a workout.
///
/// Each transition changes the phase only from the phase it belongs to, and otherwise does
/// nothing and returns false: a beat that comes out of turn, or after its sequence was stopped,
/// changes nothing.
public enum WorkoutPhase: Equatable, Sendable {
    /// No workout.
    case idle
    /// From Start's press until the workout's key has come up.
    case starting(StartBeat)
    /// A workout, at rest: the key takes a log.
    case running
    /// A workout at rest on a timed set: its "Starts in" count, then its own, which the key logs
    /// early. The one value the key, the figures' slot, the set's segment, and the count's watch
    /// read, so they never disagree on where the set is.
    case timing(CountStage)
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
    /// From End's choice until Start has come back up: the workout as it was, for the bar.
    case ending(Ending)
    /// A set logged that moves the workout on to another exercise after a rest: the row left
    /// closes, the rest counts down under it, and at its end the move goes on from its landing.
    case resting(Resting)

    /// Start's beats: `pressed`, then `growing` and `landed`, or with no motion `fadingIn`.
    /// `pressed` covers the hold after the press and the scroll to the
    /// first exercise: nothing is drawn differently between them.
    public enum StartBeat: Equatable, Sendable {
        /// Pressed: no workout yet.
        case pressed
        /// The workout exists, and the first exercise grows into the current one.
        case growing
        /// The grow has landed: Start has gone, its room kept, for one turn before the workout's
        /// key comes up.
        case landed
        /// With no motion, the list crossfades into the workout, Start gone with its room.
        case fadingIn
    }

    /// A workout ending, from End's choice until Start comes back.
    public struct Ending: Equatable, Sendable {
        /// The workout as it was, whose time fades out of its key.
        public let workout: Workout
        /// A set logged but not yet drawn when End came, kept hidden so the screen stays as drawn
        /// until the workout goes.
        public let hidden: PlannedSet?
        public fileprivate(set) var beat: Beat
        /// Whether the list still draws the workout as it was: from End's choice, which ends the
        /// stored workout at once, until the list shrinks or crossfades out of it.
        public internal(set) var drawsWorkout = true
        /// The rest showing when End came, drawn until the workout goes (`drawnRest`).
        public internal(set) var rest: Resting?
        /// The timed set's count showing when End came, drawn as it stood until the workout
        /// goes: switched to the set's plan, the slot changed as it shrank.
        public internal(set) var count: CountStage?

        /// An ending's beats, in order.
        public enum Beat: Comparable, Sendable {
            /// Begun: the key still in its bar.
            case began
            /// The key leaving, its room with it.
            case keyLeaving
            /// The time has faded out of its key, which goes.
            case timeGone
        }
    }

    /// How the key is gone from its bar.
    public enum KeyGone: Equatable, Sendable {
        /// At Start, from the grow's end until the workout's key comes up: its room in the bar
        /// stays, so the list's bottom inset doesn't change as Start goes and the next key comes.
        case keepingRoom
        /// At a workout's end, or Start's crossfade with no motion: its room goes with it.
        case givingUpRoom
    }

    /// A move from one exercise to another, from the log until the next has grown and its parts
    /// have come in.
    public struct Move: Equatable, Sendable {
        /// The set logged.
        public let set: PlannedSet
        /// Whether the next row is above the one left: round a superset's loop, or to a row moved
        /// above.
        public let isBack: Bool
        /// Whether the move goes back to a superset's member in a later round, whose first member
        /// shows the round just done until the move rolls it on.
        public let startsRound: Bool
        public internal(set) var beat: Beat
        /// Whether the move sets off from a rest, whose row has already closed: the key comes
        /// back with the next set's words, not the set logged's.
        public internal(set) var isFromRest = false

        /// A move's beats, in order.
        public enum Beat: Comparable, Sendable {
            /// Logged, and not yet drawn.
            case logged
            /// Drawn: its motion is under way.
            case shown
            /// The pulse has landed on the next row's node, which lights.
            case landed
            /// The rows have started to shift: from here the row left is shrinking.
            case shifting
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

    // MARK: Transitions

    /// Start is pressed. Only out of a workout.
    @discardableResult
    public mutating func pressStart() -> Bool {
        step(from: .idle, to: .starting(.pressed))
    }

    /// The workout exists, and the first exercise grows.
    @discardableResult
    public mutating func grow() -> Bool {
        step(from: .starting(.pressed), to: .starting(.growing))
    }

    /// The grow has landed: Start has gone, its room kept.
    @discardableResult
    public mutating func landStart() -> Bool {
        step(from: .starting(.growing), to: .starting(.landed))
    }

    /// With no motion, the workout exists and the list crossfades into it.
    @discardableResult
    public mutating func fadeIn() -> Bool {
        step(from: .starting(.pressed), to: .starting(.fadingIn))
    }

    /// Start is over: the workout's key comes up, at rest on the first set, timed (`count`, its
    /// count begun as it lands) or not.
    @discardableResult
    public mutating func run(on count: CountStage?) -> Bool {
        guard self == .starting(.landed) || self == .starting(.fadingIn) else { return false }
        self = .atRest(on: count)
        return true
    }

    /// End, with `workout` as it was: from any phase with a workout, whatever was playing. A set
    /// not yet drawn stays hidden, so the screen stays as drawn: a held set, a close's or a fade's
    /// not yet shown, and a move's until its rows start to shift, hidden again where it had
    /// shown, so what End moves, it moves from where it is drawn.
    @discardableResult
    public mutating func end(_ workout: Workout) -> Bool {
        guard canEnd else { return false }
        let hidden: PlannedSet? = switch self {
        case .idle, .starting, .running, .timing, .closing(_, true), .fadingOn(_, true), .ending:
            nil
        case let .held(set), let .closing(set, false), let .fadingOn(set, false):
            set
        case let .movingOn(move):
            move.beat < .shifting ? move.set : nil
        case let .resting(rest):
            rest.beat == .logged ? rest.set : nil
        }
        var ending = Ending(workout: workout, hidden: hidden, beat: .began)
        ending.rest = resting.flatMap { $0.beat >= .shown ? $0 : nil }
        ending.count = timing
        self = .ending(ending)
        return true
    }

    /// The key leaves as the workout ends.
    @discardableResult
    public mutating func keyLeaves() -> Bool {
        advanceEnding(from: .began, to: .keyLeaving)
    }

    /// The time has faded out of its key.
    @discardableResult
    public mutating func timeFades() -> Bool {
        advanceEnding(from: .keyLeaving, to: .timeGone)
    }

    /// The end is over: Start comes back.
    @discardableResult
    public mutating func rest() -> Bool {
        guard case let .ending(ending) = self, ending.beat == .timeGone else { return false }
        self = .idle
        return true
    }

    /// `set` was logged and stored, leading to `step`. Only at rest. `moves`: whether the screen
    /// plays motion; with none, a step to another exercise, or past the last set, is one fade.
    /// `rests`: whether a rest runs before the step to another exercise.
    @discardableResult
    public mutating func log(
        _ set: PlannedSet,
        leadingTo step: LiveWorkout.Step,
        rests: Bool = false,
        moves: Bool,
    ) -> Bool {
        guard takesLog else { return false }
        switch step {
        // A rest between sets runs with no motion too, its swap at once.
        case .nextSet where rests:
            self = .resting(Resting(
                set: set,
                isBack: false,
                isWithinExercise: true,
                beat: .logged,
            ))
        case .nextSet:
            self = .held(set)
        // With no motion too: the rest crossfades in and out.
        case let .nextExercise(_, isBack, _) where rests:
            self = .resting(Resting(
                set: set,
                isBack: isBack,
                isWithinExercise: false,
                beat: .logged,
            ))
        case let .nextExercise(_, isBack, startsRound) where moves:
            self = .movingOn(Move(
                set: set,
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

    /// The set logged is drawn: called inside the transaction that shows it. A held set shows
    /// through `rollOn(on:)`.
    @discardableResult
    public mutating func show() -> Bool {
        switch self {
        case var .movingOn(move) where move.beat == .logged:
            move.beat = .shown
            self = .movingOn(move)
        case let .closing(set, false):
            self = .closing(set, isShown: true)
        case let .fadingOn(set, false):
            self = .fadingOn(set, isShown: true)
        case var .resting(rest) where rest.beat == .logged:
            rest.beat = .shown
            self = .resting(rest)
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

    /// A move's rows start to shift. Nothing is drawn from it; End reads it.
    @discardableResult
    public mutating func shift() -> Bool {
        advance(from: .landed, to: .shifting)
    }

    /// A move's next row rolls on to its own set.
    @discardableResult
    public mutating func roll() -> Bool {
        advance(from: .shifting, to: .rolled)
    }

    /// A move, a close, or a fade is over: back at rest, on a timed set (`count`, its count begun
    /// as the move lands) or not.
    @discardableResult
    public mutating func settle(on count: CountStage?) -> Bool {
        switch self {
        case let .movingOn(move) where move.hasRolled:
            self = .atRest(on: count)
        case .closing(_, true), .fadingOn(_, true):
            self = .atRest(on: count)
        default:
            return false
        }
        return true
    }

    /// Whether there is a workout for End to end: none before Start's grow, and none once ending.
    private var canEnd: Bool {
        switch self {
        case .idle, .starting(.pressed), .ending: false
        default: true
        }
    }

    private mutating func step(from phase: Self, to next: Self) -> Bool {
        guard self == phase else { return false }
        self = next
        return true
    }

    private mutating func advanceEnding(from beat: Ending.Beat, to next: Ending.Beat) -> Bool {
        guard case var .ending(ending) = self, ending.beat == beat else { return false }
        ending.beat = next
        self = .ending(ending)
        return true
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
        case let .resting(rest) where rest.beat == .logged: [rest.set]
        case let .ending(ending): ending.hidden.map { [$0] } ?? []
        default: []
        }
    }

    /// Whether the workout moves on from a set logged: to another exercise, or past its last.
    public var isMovingOn: Bool {
        switch self {
        case .movingOn, .closing, .fadingOn: true
        // Until its close is over: the rows change height under it.
        // Between two sets of one, no row changes height.
        case let .resting(rest): !rest.isWithinExercise && rest.beat < .settled
        case .idle, .starting, .running, .timing, .held, .ending: false
        }
    }

    /// How the key is gone from its bar: as Start lands, with its room kept, until the workout's
    /// key comes up; as Start fades in with no motion, and from the key's leaving at the end to
    /// the end's rest, with its room. None while it shows. A rest's key is the screen's to take
    /// away: the bar swaps the key for −15 s and +15 s (`RoutineScreen.key(_:isOut:)`).
    public var keyGone: KeyGone? {
        switch self {
        case .starting(.landed): .keepingRoom
        case .starting(.fadingIn): .givingUpRoom
        case let .ending(ending) where ending.beat >= .keyLeaving: .givingUpRoom
        default: nil
        }
    }

    /// Whether the key takes a log: only at rest, and on a timed set once it counts. While a set
    /// is held, a second tap in its beat, as a double tap would be, is dropped; while the
    /// workout moves on, the stored workout is already past the set drawn as current, and a log
    /// taken then would land on a set, or an exercise, not yet shown.
    public var takesLog: Bool {
        self == .running || self == .timing(.counting)
    }
}

import Foundation

/// The routine screen's key at the bottom, from the workout, the phase, and where the current
/// exercise is: what it says (`role`) and what a tap on it does (`tap`), worked out in one place
/// so the two agree but where they differ on purpose. A key that still says "Log set" while the
/// current exercise is scrolled away under a finger goes back to it, since the words change only
/// once the finger lifts; "Log last set" takes no tap while its row closes.
public struct WorkoutKey: Equatable, Sendable {
    /// The workout as stored, every log in it: what a tap reads. Nil out of a workout.
    public var stored: LiveWorkout?
    /// The workout as the screen draws it, less the sets logged and not yet shown: what the
    /// words read. Nil out of a workout.
    public var shown: LiveWorkout?
    public var phase: WorkoutPhase
    /// Which way the key points back to the current exercise, as last settled: nil while it
    /// doesn't. Held while a finger is on the list.
    public var wayBack: WayBack?
    /// Whether the current exercise is scrolled away now, where a tap lands, settled or not.
    public var isScrolledAway: Bool

    public init(
        stored: LiveWorkout?,
        shown: LiveWorkout?,
        phase: WorkoutPhase,
        wayBack: WayBack?,
        isScrolledAway: Bool,
    ) {
        self.stored = stored
        self.shown = shown
        self.phase = phase
        self.wayBack = wayBack
        self.isScrolledAway = isScrolledAway
    }

    /// What the key is for, as the workout is drawn.
    public var role: Role {
        guard let shown, !phase.isStarting else { return .start }
        // While the workout moves on from a set, the key is still that set's until the next row
        // shows its own, so it changes with the row: read from the workout, it said the next
        // exercise's set ("Log left") as the pulse set off. After the last set, through the close.
        if let set = phase.keySet, let text = stored?.hiding([set]).logText {
            return .log(text)
        }
        if shown.isDone {
            return .finish
        }
        if let wayBack, let current = shown.currentExercise {
            return .back(name: current.exercise.name, isAbove: wayBack == .up)
        }
        // As drawn, the held set until the line rolls on, so the key changes with the row, not
        // before it.
        return shown.logText.map(Role.log) ?? .finish
    }

    /// What a tap on the key does, as the workout is stored. Out of a workout, Start. After the
    /// last set, Finish workout. Otherwise, where the current exercise is scrolled away when the
    /// tap lands, back to it, nothing logged. Nothing while the workout moves on, and nothing
    /// while a set just logged is held, as a double tap's second tap would land.
    public var tap: Tap {
        guard let stored, !phase.isStarting else { return .start }
        guard !phase.isMovingOn else { return .nothing }
        if stored.isDone {
            return .finish
        }
        guard let current = stored.currentExercise, let set = stored.currentSet else {
            return .nothing
        }
        if wayBack != nil || isScrolledAway {
            return .back
        }
        guard phase.takesLog else { return .nothing }
        return .log(
            set,
            of: current,
            impact: set.side == nil ? .set : .side,
            leadingTo: stored.step(logging: set),
        )
    }
}

extension WorkoutKey {
    /// Which way the current exercise is, scrolled away: above the part of the list showing, or
    /// below it.
    public enum WayBack: Equatable, Sendable {
        case up
        case down
    }

    /// What the key is for now.
    public enum Role: Equatable, Identifiable, Sendable {
        case start
        /// Logs the current set, saying which ("Log set", "Log left", "Log last set"). After the
        /// last set, as its row closes, it still says "Log last set", and takes no tap.
        case log(String)
        /// The current exercise is scrolled away, above it or not: the key goes back to it.
        case back(name: String, isAbove: Bool)
        case finish

        /// Which key this is: a change of kind swaps the key for another, a change within one,
        /// as "Log left" to "Log right", changes its words.
        public enum Kind: Hashable, Sendable {
            case start
            case log
            case back
            case finish
        }

        public var kind: Kind {
            switch self {
            case .start: .start
            case .log: .log
            case .back: .back
            case .finish: .finish
            }
        }

        /// The key's identity in its bar, which swaps it for another as it changes.
        public var id: Kind {
            kind
        }
    }

    /// What a tap on the key does.
    public enum Tap: Equatable, Sendable {
        case start
        /// Logs `set` of its exercise, with the haptic `impact`, leading to the step shown next,
        /// from the workout before it.
        case log(PlannedSet, of: RoutineExercise, impact: Impact, leadingTo: LiveWorkout.Step)
        /// Goes back to the current exercise, logging nothing.
        case back
        case finish
        case nothing
    }

    /// The haptic a log plays: a set's is heavier than one side's.
    public enum Impact: Equatable, Sendable {
        case set
        case side
    }
}

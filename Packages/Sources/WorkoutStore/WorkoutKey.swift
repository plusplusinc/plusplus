import Foundation

/// The routine screen's key at the bottom, from the workout, the phase, and where the current
/// exercise is: what it says (`role`) and what a tap on it does (`tap`), worked out in one place
/// so the two agree, except where they differ on purpose. A key that still says "Log set" while
/// the current exercise is scrolled away under a finger goes back to it, since the words change
/// only once the finger lifts; "Log last set" takes no tap while its row closes; and as a
/// workout ends, the key keeps its words while a tap is Start's, which does nothing until Start
/// is back. What a tap lands on (a sheet over the key, the key out in a swap) is the screen's.
/// During a rest the key is −15 s and +15 s (`Role.rest`), whose taps are `restTap(by:)`'s.
public struct WorkoutKey: Sendable {
    /// The workout as stored, every log in it: what a tap reads. Nil out of a workout, and from
    /// End's choice.
    public let stored: LiveWorkout?
    /// The workout as the screen draws it, less the sets logged and not yet shown: what the
    /// words read. Nil out of a workout.
    public let shown: LiveWorkout?
    public let phase: WorkoutPhase
    /// Which way the key points back to the current exercise, as last settled: nil while it
    /// doesn't. Held while a finger is on the list.
    public let wayBack: WayBack?
    /// Whether the current exercise is scrolled away now, where a tap lands, settled or not.
    public let isScrolledAway: Bool

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

    /// The timed set's count as the key draws it, from the phase alone: "Starts in" or the
    /// count, at rest on a timed set (`WorkoutPhase.timing`); a timed set just logged and still
    /// drawn, held full for its beat (held, as between a side plank's sides, moving on until the
    /// rows shift, or before its rest shows), as a count, so the key swaps once, from it to
    /// what follows; out of a rest onto a timed set, its count, which the rest's end began; and
    /// on the way to a timed set with no rest before it (Start, or a move once the rows shift),
    /// "Starts in". Nil for a reps set.
    public var drawnCount: CountStage? {
        if let logged = phase.loggedAndDrawn {
            return stored?.loggedCount(of: logged) == nil ? nil : .counting
        }
        if let stage = phase.timing {
            return stage
        }
        guard shown?.isOnTimedSet == true, phase.isMovingOn || phase.isLeavingRest else {
            return nil
        }
        return phase.isLeavingRest ? .counting : .startsIn
    }

    /// What the key is for, as the workout is drawn.
    public var role: Role {
        guard let shown, !phase.isStarting else { return .start }
        // While the workout moves on from a set, the key is still that set's until the next row
        // shows its own, so it changes with the row: read from the workout, it said the next
        // exercise's set ("Log left") as the pulse set off. After the last set, through the close.
        if let set = phase.keySet, let text = stored?.hiding([set]).logText {
            return logRole(text)
        }
        if shown.isDone {
            return .finish
        }
        if let wayBack, let current = shown.currentExercise {
            return .back(name: current.exercise.name, isAbove: wayBack == .up)
        }
        // As drawn, the held set until the line rolls on, so the key changes with the row, not
        // before it.
        return shown.logText.map(logRole) ?? .finish
    }

    /// The log key saying `text`, or during a rest −15 s and +15 s in its place: from the log of
    /// a set with a rest after it until the rest ends, and through End's leaving of a rest.
    private func logRole(_ text: String) -> Role {
        let isResting = phase.drawnRest.map { $0.beat < .returning } ?? false
        if isResting {
            return .rest
        }
        return switch drawnCount {
        case .startsIn: .startNow
        case .counting: .count(String(localized: "Log early"))
        case nil: .log(text)
        }
    }

    /// What a tap on +15 s does: adds to the set counting, once it counts.
    public func countTap(by seconds: Int) -> Tap {
        phase.timing == .counting ? .extendCount(by: seconds) : .nothing
    }

    /// What the count reaching zero does: logs the set, with the heavy tap, as a tap on the key
    /// would, whether or not the exercise is scrolled away or a sheet covers the key. Nothing
    /// unless the set counts at rest.
    public var runOut: Tap {
        guard phase.timing == .counting, let stored,
              let current = stored.currentExercise,
              let set = stored.currentSet
        else { return .nothing }
        return .log(set, of: current, impact: .runOut, leadingTo: stored.step(logging: set))
    }

    /// What a tap on −15 s or +15 s does: changes the rest running by `seconds`, once it has
    /// come in (between exercises, once the pulse has landed at it; between sets, once the swap
    /// is over), so a double tap's second on Log set, landing on −15 s as it swaps in, changes
    /// nothing; nothing once the rest is over.
    public func restTap(by seconds: Int) -> Tap {
        guard let rest = phase.resting, rest.beat < .returning,
              rest.beat >= (rest.isWithinExercise ? .settled : .landed)
        else { return .nothing }
        return .adjustRest(by: seconds)
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
        if phase.timing == .startsIn {
            return .startNow
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
        /// During a rest, −15 s and +15 s in the log key's place: another key, so they swap with
        /// it as any two keys do, never crossfading through it in its place.
        case rest
        /// During a timed set's "Starts in", the key that starts it now.
        case startNow
        /// A timed set counting: its log key, saying which as `log` does, filling as it counts,
        /// with +15 s beside it. Another key than `log`, which the bar swaps in.
        case count(String)

        /// Which key this is: a change of kind swaps the key for another, a change within one,
        /// as "Log left" to "Log right", changes its words.
        public enum Kind: Hashable, Sendable {
            case start
            case log
            case back
            case finish
            case rest
            case startNow
            case count
        }

        public var kind: Kind {
            switch self {
            case .start: .start
            case .log: .log
            case .back: .back
            case .finish: .finish
            case .rest: .rest
            case .startNow: .startNow
            case .count: .count
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
        /// −15 s or +15 s: the rest running changes by `seconds`.
        case adjustRest(by: Int)
        /// "Start now": the timed set counts from now.
        case startNow
        /// +15 s: the timed set counting gets `by` seconds more.
        case extendCount(by: Int)
        case nothing
    }

    /// The haptic a log plays: a set's is heavier than one side's, and a timed set's own end
    /// heaviest, so it is felt with the phone set down.
    public enum Impact: Equatable, Sendable {
        case set
        case side
        case runOut
    }
}

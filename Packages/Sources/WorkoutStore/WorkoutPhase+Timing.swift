extension WorkoutPhase {
    /// At rest on a set: timed, at its count's `count`, or not, with none.
    static func atRest(on count: CountStage?) -> Self {
        count.map(timing) ?? .running
    }

    /// A held set's beat is over: the line rolls on, and the workout is at rest on the next set,
    /// timed (`count`, its count begun as it shows) or not.
    @discardableResult
    public mutating func rollOn(on count: CountStage?) -> Bool {
        guard case .held = self else { return false }
        self = .atRest(on: count)
        return true
    }

    /// "Starts in" is over, by its run to 0 or "Start now": the set counts. Only from
    /// "Starts in".
    @discardableResult
    public mutating func startCount() -> Bool {
        guard self == .timing(.startsIn) else { return false }
        self = .timing(.counting)
        return true
    }

    /// Whether the workout is at rest on a set, timed or not: the key's tap is the set's.
    public var isAtRest: Bool {
        self == .running || timing != nil
    }

    /// The timed set's count while the workout is at rest on one.
    public var timing: CountStage? {
        guard case let .timing(stage) = self else { return nil }
        return stage
    }

    /// Coming back to a set out of a rest, whose end began the set's count: within one exercise
    /// as it swaps back, or on a move from the rest's word. A timed set then already counts.
    public var isLeavingRest: Bool {
        resting?.beat == .returning || move?.isFromRest == true
    }

    /// The set just logged, still drawn: held, moving on until the rows shift, closing, fading
    /// on, or before its rest shows. A timed one keeps its count where the log stopped it.
    public var loggedAndDrawn: PlannedSet? {
        switch self {
        case let .held(set), let .closing(set, _), let .fadingOn(set, _): set
        case let .movingOn(move) where move.beat < .shifting && !move.isFromRest: move.set
        case let .resting(rest) where rest.beat == .logged: rest.set
        default: nil
        }
    }
}

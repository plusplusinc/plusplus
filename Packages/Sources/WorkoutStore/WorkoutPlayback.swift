import Foundation

/// Which logged sets a screen has yet to show, and the step it is playing. A log is stored at
/// once; its step plays when nothing else does, so a log that arrives while a move plays waits
/// its turn, never dropped, and the screen draws the workout without it until then.
public struct WorkoutPlayback: Equatable, Sendable {
    /// The step being played, for the set whose log it follows.
    public struct Playing: Equatable, Sendable {
        public let set: PlannedSet
        public let step: LiveWorkout.Step
        /// Whether the screen draws the set yet: from the transaction that shows it.
        public var isShown: Bool
    }

    public private(set) var playing: Playing?
    /// Logged and stored, not yet drawn, oldest first: the playing step's set until its motion
    /// shows it, then every set waiting its turn.
    public private(set) var unshown: [PlannedSet] = []

    public init() { }

    /// A set was logged. True when its step starts now: nothing plays and nothing waits.
    public mutating func log(_ set: PlannedSet) -> Bool {
        let startsNow = playing == nil && unshown.isEmpty
        unshown.append(set)
        return startsNow
    }

    /// `set`'s step starts to play.
    public mutating func start(_ step: LiveWorkout.Step, for set: PlannedSet) {
        playing = Playing(set: set, step: step, isShown: false)
    }

    /// The playing step's set is drawn: called inside the transaction that shows it.
    public mutating func show() {
        guard let set = playing?.set else { return }
        playing?.isShown = true
        unshown.removeAll { $0 == set }
    }

    /// The playing step is over. Returns the set waiting longest, whose step starts now.
    public mutating func end() -> PlannedSet? {
        playing = nil
        return unshown.first
    }

    /// The set logged that stays on its exercise, shown as still to do until the line rolls on.
    public var held: PlannedSet? {
        guard let playing, playing.step == .nextSet, !playing.isShown else { return nil }
        return playing.set
    }

    /// Whether the step playing moves the workout on: to another exercise, or past its last set.
    public var isMovingOn: Bool {
        guard let step = playing?.step else { return false }
        return step != .nextSet
    }
}

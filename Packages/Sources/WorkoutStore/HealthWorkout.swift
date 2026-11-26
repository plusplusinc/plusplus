import Foundation

/// The kinds of workout the app saves to Apple Health, in its own words; the Health target maps
/// each to Health's type.
public enum HealthActivity: Equatable, Sendable {
    /// Mostly exercises with a weight.
    case traditionalStrength
}

/// What Apple Health gets for a finished workout: its type, its start and end, and its pauses,
/// which Health leaves out of the length. Nothing else: no calories, none being measured.
public struct HealthWorkout: Equatable, Sendable {
    /// The logged workout it was made from.
    public let id: LoggedWorkout.ID
    public let activity: HealthActivity
    public let start: Date
    public let end: Date
    /// Each pause, from when it began to when it ended, in order.
    public let pauses: [DateInterval]

    public init(
        id: LoggedWorkout.ID,
        activity: HealthActivity,
        start: Date,
        end: Date,
        pauses: [DateInterval],
    ) {
        self.id = id
        self.activity = activity
        self.start = start
        self.end = end
        self.pauses = pauses
    }

    /// Why a finished workout goes nowhere.
    public enum Withheld: Error, Equatable, Sendable {
        /// It hasn't ended.
        case notFinished
        /// It was paused and resumed before its finish. The store keeps a resumed pause's
        /// length but not when it happened, and Health takes a pause only at its times, so it
        /// would go either with its pauses counted in its length or with a pause made up.
        case resumedBefore
    }

    /// The workout for `finished`, whose pauses resumed before the finish came to
    /// `resumedSeconds` (the paused seconds it had just before), and which was paused from
    /// `pausedSince` until its finish, if it was.
    public init(
        finished: LoggedWorkout,
        resumedSeconds: Double,
        pausedSince: Date?,
    ) throws(Withheld) {
        guard let end = finished.endedAt else { throw .notFinished }
        guard resumedSeconds == 0 else { throw .resumedBefore }
        let lastPause = pausedSince.map { DateInterval(start: min($0, end), end: end) }
        self.init(
            id: finished.id,
            // Every workout is strength training for now; the type per workout comes next.
            activity: .traditionalStrength,
            start: finished.startedAt,
            end: end,
            pauses: lastPause.map { [$0] } ?? [],
        )
    }
}

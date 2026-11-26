import Foundation

/// The kinds of workout the app saves to Apple Health, in its own words; the Health target maps
/// each to Health's type.
public enum HealthActivity: Equatable, Sendable {
    /// Mostly strength exercises, at least half of them holding a weight.
    case traditionalStrength
    /// Mostly strength exercises, most of them holding no weight.
    case functionalStrength
    /// Mostly conditioning exercises.
    case highIntensityIntervals
    /// Mostly stretches.
    case flexibility

    /// The type for a workout of `exercises`, each counted once per place: by the kind most of
    /// them are (`[Exercise].kind`), the one a workout's row reads, and for strength by its
    /// strength exercises alone, the others leaving the weights' share unchanged. Counted by
    /// exercise, not set, as that kind is. Weights are what holds a weight (`Exercise.load`),
    /// so a pull-up's bar, a band, or a bench alone is bodyweight. An even split, and no
    /// exercises at all, is traditional strength.
    public init(exercises: [Exercise]) {
        switch exercises.kind {
        case .stretch: self = .flexibility
        case .conditioning: self = .highIntensityIntervals
        case .strength:
            let strength = exercises.filter { $0.kind == .strength }
            let weighted = strength.count { $0.load != nil }
            self = weighted * 2 >= strength.count ? .traditionalStrength : .functionalStrength
        }
    }
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
    /// `pausedSince` until its finish, if it was. Its type is from the exercises it logged
    /// sets of, each once, as they are in `list`; one since deleted is left out. From what was
    /// done, not the workout's plan, which can change before a later save.
    public init(
        finished: LoggedWorkout,
        in list: ExerciseList,
        resumedSeconds: Double,
        pausedSince: Date?,
    ) throws(Withheld) {
        guard let end = finished.endedAt else { throw .notFinished }
        guard resumedSeconds == 0 else { throw .resumedBefore }
        let lastPause = pausedSince.map { DateInterval(start: min($0, end), end: end) }
        self.init(
            id: finished.id,
            activity: HealthActivity(
                exercises: finished.loggedExercises(in: list).compactMap(\.exercise),
            ),
            start: finished.startedAt,
            end: end,
            pauses: lastPause.map { [$0] } ?? [],
        )
    }
}

import Foundation

/// The kinds of workout the app saves to Apple Health, in its own words; the Health target maps
/// each to Health's type. Stored as its raw string with a finished workout.
public enum HealthActivity: String, Equatable, Sendable {
    /// Mostly strength exercises, at least half of them holding a weight.
    case traditionalStrength
    /// Mostly strength exercises, most of them holding no weight.
    case functionalStrength
    /// Mostly conditioning exercises.
    case highIntensityIntervals
    /// Mostly stretches.
    case flexibility

    /// The type for a workout of `exercises`, by their kind (`[Exercise].kind`); for strength,
    /// by the share of its strength exercises alone that hold a weight (`Exercise.load`), so a
    /// pull-up's bar, a band, or a bench alone is bodyweight. Half or more is traditional, as
    /// are no exercises at all.
    init(exercises: [Exercise]) {
        switch exercises.kind {
        case .stretch: self = .flexibility
        case .conditioning: self = .highIntensityIntervals
        case .strength:
            let strength = exercises.filter { $0.kind == .strength }
            let weighted = strength.count { $0.load != nil }
            self = weighted * 2 >= strength.count ? .traditionalStrength : .functionalStrength
        }
    }

    /// The type for a workout that logged `sets`: from the rows it logged sets of, each row's
    /// exercise once as it is in `list`, so an exercise in two rows counts twice, as the
    /// workout's row counts it (`Workout.summary`); one since deleted is left out. From what
    /// was done, not the workout's plan.
    public init(logged sets: [LoggedSet], in list: ExerciseList) {
        var rows: Set<WorkoutExercise.ID> = []
        self.init(exercises: sets
            .filter { rows.insert($0.row).inserted }
            .compactMap { list.exercise(id: $0.exerciseID) })
    }
}

/// What Apple Health gets for a finished workout: its type, its start and end, and its pauses,
/// which Health leaves out of the length. Nothing else: no calories, none being measured.
public struct HealthWorkout: Equatable, Sendable {
    /// The workout session it was made from.
    public let id: WorkoutSession.ID
    public let activity: HealthActivity
    public let start: Date
    public let end: Date
    /// Each pause, from when it began to when it ended, in order.
    public let pauses: [DateInterval]

    public init(
        id: WorkoutSession.ID,
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

    /// Why a finished workout goes nowhere (`WorkoutSession.healthWithheld`).
    public enum Withheld: Error, Equatable, Sendable {
        /// It hasn't ended.
        case notFinished
        /// Its end isn't after its start, as with a device clock set back.
        case noLength
        /// Its kept pauses don't account for its time paused, as for one paused before the
        /// store kept a pause's times (V14). Health takes a pause only at its times, so it
        /// would go either with its pauses counted in its length or with a pause made up.
        case timesNotKept
    }

    /// The workout for `finished`, from what the store keeps of it alone, when Health can have
    /// it (`WorkoutSession.healthWithheld`). Its type is the one worked out at Finish, else, for
    /// a workout finished before that was kept, from what it logged as `list` has it now
    /// (`HealthActivity(logged:in:)`).
    public init(_ finished: WorkoutSession, in list: ExerciseList) throws(Withheld) {
        if let withheld = finished.healthWithheld {
            throw withheld
        }
        guard let end = finished.endedAt else { throw .notFinished }
        self.init(
            id: finished.id,
            activity: finished.healthActivity ?? HealthActivity(logged: finished.sets, in: list),
            start: finished.startedAt,
            end: end,
            pauses: finished.pauses,
        )
    }
}

import Foundation

/// A set as a workout did it: the numbers it was done at, beside the ones planned for it. The
/// two start equal; apart from the start, so fixing a logged set later changes only what was
/// done.
public struct LoggedSet: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The routine row it was a set of.
    public let row: WorkoutExercise.ID
    /// The exercise's `Exercise.id`, so the set still reads once its row is deleted.
    public let exerciseID: String
    /// The exercise's name when the set was logged, kept through a rename or a delete; nil for
    /// a set logged before names were kept, which reads as its exercise's name now.
    public let exerciseName: String?
    public let round: Int
    public let side: Side?
    /// Reps or time, as done.
    public var target: SetTarget
    /// As done; nil for an exercise with no load.
    public var weight: Weight?
    public let plannedTarget: SetTarget
    public let plannedWeight: Weight?
    public let loggedAt: Date
    /// Where the workout's clock stood at the log, pauses left out (`LoggedWorkout.clock(at:)`):
    /// where the rest after it starts. Nil for a set logged before V11 kept it, which rests for
    /// none.
    public var clockWhenLogged: Double?
    /// The rest after this set against the routine's, in seconds: its +15 s taps, and a skip's cut
    /// to the seconds rested (`LiveWorkout.skippingRest(override:at:)`).
    public var restAdjustment = 0
    /// The +15 s taps on this set's own count, a timed set's, in seconds.
    public var timeAdded = 0

    public init(
        id: UUID = UUID(),
        row: WorkoutExercise.ID,
        exerciseID: String,
        exerciseName: String?,
        round: Int,
        side: Side?,
        target: SetTarget,
        weight: Weight?,
        plannedTarget: SetTarget,
        plannedWeight: Weight?,
        loggedAt: Date,
    ) {
        self.id = id
        self.row = row
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.round = round
        self.side = side
        self.target = target
        self.weight = weight
        self.plannedTarget = plannedTarget
        self.plannedWeight = plannedWeight
        self.loggedAt = loggedAt
    }

    /// The set of the routine it was.
    public var planned: PlannedSet {
        PlannedSet(row: row, round: round, side: side)
    }
}

import Foundation

/// A set as a workout did it: the numbers it was done at, beside the ones planned for it. The
/// two start equal; apart from the start, so fixing a logged set later changes only what was
/// done.
public struct LoggedSet: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The routine row it was a set of.
    public let row: RoutineExercise.ID
    /// The exercise's slug, so the set still reads once its row is deleted.
    public let exerciseID: String
    public let round: Int
    public let side: Side?
    /// Reps or time, as done.
    public var target: SetTarget
    /// As done; nil for an exercise with no load.
    public var weight: Weight?
    public let plannedTarget: SetTarget
    public let plannedWeight: Weight?
    public let loggedAt: Date

    public init(
        id: UUID = UUID(),
        row: RoutineExercise.ID,
        exerciseID: String,
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

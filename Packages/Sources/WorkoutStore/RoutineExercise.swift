import Foundation

/// An exercise as it appears in a routine. Its own id is what lets the same exercise appear
/// more than once, each row its own, and keeps a row the same row across launches.
public struct RoutineExercise: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let exercise: Exercise
    /// This row's values, its exercise's defaults until changed.
    public var plan: ExercisePlan
    /// The superset the row is in, shared by the rows next to it in the same one; nil for a
    /// plain row. `Routine` keeps supersets whole and at least two rows long.
    public var supersetID: UUID?

    public init(
        id: UUID = UUID(),
        exercise: Exercise,
        plan: ExercisePlan,
        supersetID: UUID? = nil,
    ) {
        self.id = id
        self.exercise = exercise
        self.plan = plan
        self.supersetID = supersetID
    }

    /// A new row, at its exercise's defaults, a weight in `weightUnit`, the region's.
    public init(id: UUID = UUID(), exercise: Exercise, weightUnit: WeightUnit) {
        self.init(id: id, exercise: exercise, plan: exercise.defaultPlan(in: weightUnit))
    }
}

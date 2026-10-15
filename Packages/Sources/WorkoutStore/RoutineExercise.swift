import Foundation

/// An exercise as it appears in a routine. Its own id is what lets the same exercise appear
/// more than once, each row its own, and keeps a row the same row across launches.
public struct RoutineExercise: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let exercise: Exercise
    /// This row's values, its exercise's defaults until changed.
    public var plan: ExercisePlan

    public init(id: UUID = UUID(), exercise: Exercise, plan: ExercisePlan? = nil) {
        self.id = id
        self.exercise = exercise
        self.plan = plan ?? exercise.defaultPlan
    }
}

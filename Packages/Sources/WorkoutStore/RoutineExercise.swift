import Foundation

/// An exercise as it appears in a routine. Its own id is what lets the same exercise appear
/// more than once, each row its own.
public struct RoutineExercise: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let exercise: Exercise

    public init(exercise: Exercise) {
        self.exercise = exercise
    }
}

import Foundation

/// A workout as the app works with it: a value, saved through `Store`.
public struct Workout: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The name the user chose; empty when they haven't.
    public var name: String
    public var exercises: [WorkoutExercise]

    public init(id: UUID = UUID(), name: String = "", exercises: [WorkoutExercise] = []) {
        self.id = id
        self.name = name
        self.exercises = exercises
    }

    /// Nothing the user put there: no name and no exercises. Never stored.
    public var isEmpty: Bool {
        name.isEmpty && exercises.isEmpty
    }
}

import Foundation

/// Per-entity file envelopes for the repo layout (docs/PLATFORM.md): each
/// file in `program/exercises/`, `program/workouts/`, and `history/` wraps
/// one DTO together with the schema version, so every file stands alone.

public struct ExerciseDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exercise: ExerciseDTO

    public init(exercise: ExerciseDTO) {
        self.schemaVersion = Interchange.schemaVersion
        self.exercise = exercise
    }
}

public struct WorkoutDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var workout: WorkoutDTO

    public init(workout: WorkoutDTO) {
        self.schemaVersion = Interchange.schemaVersion
        self.workout = workout
    }
}

public struct SessionDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var session: SessionDTO

    public init(session: SessionDTO) {
        self.schemaVersion = Interchange.schemaVersion
        self.session = session
    }
}

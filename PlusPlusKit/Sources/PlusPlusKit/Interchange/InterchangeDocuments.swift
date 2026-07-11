import Foundation

/// Per-entity file envelopes for the repo layout (docs/PLATFORM.md): each
/// file in `program/exercises/`, `program/routines/`, and `history/` wraps
/// one DTO together with the schema version, so every file stands alone.

public struct ExerciseDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exercise: ExerciseDTO

    public init(exercise: ExerciseDTO) {
        self.schemaVersion = Interchange.schemaVersion
        self.exercise = exercise
    }
}

public struct RoutineDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var routine: RoutineDTO

    public init(routine: RoutineDTO) {
        self.schemaVersion = Interchange.schemaVersion
        self.routine = routine
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

public struct EquipmentLibraryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var library: EquipmentLibraryDTO

    public init(library: EquipmentLibraryDTO) {
        self.schemaVersion = Interchange.schemaVersion
        self.library = library
    }
}

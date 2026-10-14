import Foundation

/// A routine as the app works with it: a value, saved through `RoutineStore`.
public struct Routine: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The name the user chose; empty when they haven't.
    public var name: String
    public var exercises: [RoutineExercise]
    /// The name suggested for an unnamed routine from its exercises, kept so a relaunch shows
    /// it at once instead of asking again.
    public var generatedName: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        exercises: [RoutineExercise] = [],
        generatedName: String? = nil,
    ) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.generatedName = generatedName
    }

    /// Nothing the user put there: no name and no exercises. Never stored.
    public var isEmpty: Bool {
        name.isEmpty && exercises.isEmpty
    }
}

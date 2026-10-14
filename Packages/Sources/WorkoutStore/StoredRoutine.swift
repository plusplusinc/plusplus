import Foundation
import SwiftData

// The stored shape of a routine. The class names will be CloudKit record types once sync is
// on, so they are final now. Every rule in swiftdata.md holds: defaults or optionals, nothing
// unique, an optional relationship with an inverse.

@Model
final class StoredRoutine {
    var id = UUID()
    /// Empty when unnamed.
    var name = ""
    var generatedName: String?
    /// When the name or the rows last changed: the launch rule opens the latest.
    var editedAt = Date.distantPast
    @Relationship(deleteRule: .cascade, inverse: \StoredRoutineExercise.routine)
    var exercises: [StoredRoutineExercise]? = []

    init(id: UUID) {
        self.id = id
    }
}

@Model
final class StoredRoutineExercise {
    /// The row's own identity, so duplicates of an exercise stay apart.
    var id = UUID()
    /// The built-in exercise's slug, `Exercise.id`.
    var exerciseID = ""
    /// A relationship is unordered, so the row carries its place.
    var position = 0
    var routine: StoredRoutine?

    init(id: UUID, exerciseID: String, position: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.position = position
    }
}

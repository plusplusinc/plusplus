import Foundation
import SwiftData

typealias StoredExercise = StoreSchemaV15.StoredExercise

extension StoredExercise {
    /// The exercise as set, or nil for a measure this build doesn't know, or muscle groups none of
    /// which it knows, from a newer version: left out of the list rather than read as something
    /// else. None stored at all is an exercise that works none. An unknown group or piece of
    /// equipment beside known ones is left out of its set.
    var created: CreatedExercise? {
        let groups = Set<MuscleGroup>(stored: muscleGroups)
        guard groups.isEmpty == muscleGroups.isEmpty,
              let measure = Measure(rawValue: measure) else { return nil }
        return CreatedExercise(
            id: id,
            name: name,
            muscleGroups: groups,
            equipment: Set(stored: equipment),
            measure: measure,
            isPerSide: isPerSide,
            createdAt: createdAt,
        )
    }

    /// Sets only the fields that changed, so an unchanged exercise stays clean.
    func write(_ created: CreatedExercise) {
        update(\.name, to: created.name)
        update(\.muscleGroups, to: created.muscleGroups.stored)
        update(\.equipment, to: created.equipment.stored)
        update(\.measure, to: created.measure.rawValue)
        update(\.isPerSide, to: created.isPerSide)
        update(\.createdAt, to: created.createdAt)
    }
}

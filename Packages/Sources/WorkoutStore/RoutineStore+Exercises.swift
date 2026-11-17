import Foundation
import SwiftData

extension RoutineStore {
    /// The routine `id` as stored, its rows read through today's exercises, without marking it
    /// opened; nil if there is none.
    public func routine(_ id: Routine.ID, weightUnit: WeightUnit) throws -> Routine? {
        var descriptor = FetchDescriptor<StoredRoutine>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return nil }
        return try Self.routine(from: stored, exercises: exercises(), weightUnit: weightUnit)
    }

    /// Deletes the created exercise `id` and every routine row that uses it, in one save. A
    /// routine left with nothing, no name and no rows, goes too, as a cleared one does; one
    /// left with a superset of one reads it as a plain row. Logged sets keep the exercise's id
    /// and name, so they still read.
    public func deleteExercise(_ id: String) throws {
        let exercises = try modelContext.fetch(FetchDescriptor<StoredExercise>(
            predicate: #Predicate { $0.id == id },
        ))
        for exercise in exercises {
            modelContext.delete(exercise)
        }
        let rows = try modelContext.fetch(FetchDescriptor<StoredRoutineExercise>(
            predicate: #Predicate { $0.exerciseID == id },
        ))
        var touched: [StoredRoutine] = []
        for row in rows {
            if let routine = row.routine, !touched.contains(where: { $0 === routine }) {
                touched.append(routine)
            }
            modelContext.delete(row)
        }
        for routine in touched {
            let left = (routine.exercises ?? []).filter { $0.exerciseID != id }
            if routine.name.isEmpty, left.isEmpty {
                modelContext.delete(routine)
            }
        }
        try modelContext.save()
    }
}

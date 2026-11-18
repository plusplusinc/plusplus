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

    /// Stores a built-in's customization in place of any it had; an empty one deletes it.
    public func save(_ customization: Customization) throws {
        guard !customization.isEmpty else {
            try clearCustomizations(customization.exerciseID)
            return
        }
        let id = customization.exerciseID
        let shipped = ExerciseList.builtIn.exercise(id: id)
        try keepLoggedNames(
            of: id,
            renamedTo: shipped.map { customization.applied(to: $0.settings).name },
        )
        let stored = try modelContext.fetch(FetchDescriptor<StoredCustomization>(
            predicate: #Predicate { $0.exerciseID == id },
        ))
        // One per built-in: any other sync left goes.
        for extra in stored.dropFirst() {
            modelContext.delete(extra)
        }
        let target = stored.first ?? {
            let new = StoredCustomization(exerciseID: id)
            modelContext.insert(new)
            return new
        }()
        target.write(customization, at: .now)
        try modelContext.save()
    }

    /// Deletes the built-in `id`'s customization, so it reads as it shipped.
    public func clearCustomizations(_ id: String) throws {
        try keepLoggedNames(of: id, renamedTo: ExerciseList.builtIn.exercise(id: id)?.name)
        for stored in try modelContext.fetch(FetchDescriptor<StoredCustomization>(
            predicate: #Predicate { $0.exerciseID == id },
        )) {
            modelContext.delete(stored)
        }
        try modelContext.save()
    }

    /// Before the exercise `id` is renamed to `name`, gives each of its logged sets with no name
    /// (logged before V9 stored one) the name it reads now, so it keeps the name it was logged
    /// under. Saved with the rename.
    func keepLoggedNames(of id: String, renamedTo name: String?) throws {
        guard let current = try exercises().exercise(id: id)?.name, current != name else { return }
        let unnamed = try modelContext.fetch(FetchDescriptor<StoredSet>(
            predicate: #Predicate { $0.exerciseID == id && $0.exerciseName == nil },
        ))
        for set in unnamed {
            set.exerciseName = current
        }
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

import Foundation
import SwiftData

extension Store {
    /// The workout `id` as stored, its rows read through today's exercises, without marking it
    /// opened; nil if there is none.
    public func workout(_ id: Workout.ID, weightUnit: WeightUnit) throws -> Workout? {
        var descriptor = FetchDescriptor<StoredRoutine>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return nil }
        return try Self.workout(from: stored, exercises: exercises(), weightUnit: weightUnit)
    }

    /// Stores a built-in's customization in place of any it had; an empty one deletes it.
    public func save(_ customization: Customization) throws {
        guard !customization.isEmpty else {
            try clearCustomizations(customization.exerciseID)
            return
        }
        let id = customization.exerciseID
        guard let shipped = Exercise.builtIn(id: id) else { return }
        let stored = try storedCustomizations(of: id)
        try keepLoggedNames(
            of: id,
            named: name(of: shipped, customizedBy: stored.first),
            renamedTo: customization.applied(to: shipped.settings).name,
        )
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
        let stored = try storedCustomizations(of: id)
        if let shipped = Exercise.builtIn(id: id) {
            try keepLoggedNames(
                of: id,
                named: name(of: shipped, customizedBy: stored.first),
                renamedTo: shipped.name,
            )
        }
        for customization in stored {
            modelContext.delete(customization)
        }
        try modelContext.save()
    }

    /// The built-in `id`'s stored customizations, the latest edited first.
    private func storedCustomizations(of id: String) throws -> [StoredCustomization] {
        try modelContext.fetch(FetchDescriptor<StoredCustomization>(
            predicate: #Predicate { $0.exerciseID == id },
            sortBy: [SortDescriptor(\.editedAt, order: .reverse)],
        ))
    }

    /// The name `shipped` reads under `stored`, or as shipped with none.
    private func name(of shipped: Exercise, customizedBy stored: StoredCustomization?) -> String {
        stored.map { $0.customization.applied(to: shipped.settings).name } ?? shipped.name
    }

    /// Before the exercise `id`, now named `current` (nil when not yet stored), is renamed to
    /// `name`, gives each of its logged sets with no name (logged before V9 stored one) the name
    /// it reads now, so it keeps the name it was logged under. Saved with the rename.
    func keepLoggedNames(of id: String, named current: String?, renamedTo name: String) throws {
        guard let current, current != name else { return }
        let unnamed = try modelContext.fetch(FetchDescriptor<StoredSet>(
            predicate: #Predicate { $0.exerciseID == id && $0.exerciseName == nil },
        ))
        for set in unnamed {
            set.exerciseName = current
        }
    }

    /// Deletes the created exercise `id` and every workout row that uses it, in one save. A
    /// workout left with nothing, no name and no rows, goes too, as a cleared one does; one
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
            if let workout = row.routine, !touched.contains(where: { $0 === workout }) {
                touched.append(workout)
            }
            modelContext.delete(row)
        }
        for workout in touched {
            let left = (workout.exercises ?? []).filter { $0.exerciseID != id }
            if workout.name.isEmpty, left.isEmpty {
                modelContext.delete(workout)
            }
        }
        try modelContext.save()
    }
}

import Foundation
import OSLog
import SwiftData

/// Saves routines and finds the one the app opens with. Values in, values out: the stored
/// models never leave the actor.
@ModelActor
public actor RoutineStore {
    private static let builtInByID = Dictionary(
        uniqueKeysWithValues: Exercise.builtIn.map { ($0.id, $0) },
    )

    static let schema = Schema([StoredRoutine.self, StoredRoutineExercise.self])

    public static func open(_ mode: StorageMode) throws -> RoutineStore {
        try RoutineStore(modelContainer: WorkoutStoreContainer.make(mode: mode, schema: schema))
    }

    /// The routine the app opens with, or nil for a new one: the last one opened or edited.
    /// Every stored routine has been edited, since an untouched one is never saved and a
    /// cleared one is deleted. A weight never saved reads as its exercise's default in
    /// `weightUnit`.
    public func launchRoutine(weightUnit: WeightUnit) throws -> Routine? {
        let edited = try latest(by: SortDescriptor(\.editedAt, order: .reverse))
        let opened = try latest(by: SortDescriptor(\.openedAt, order: .reverse))
        // A tie is the same moment; the edit wins it.
        let launched = switch (edited, opened) {
        case let (edited?, opened?): opened.openedAt > edited.editedAt ? opened : edited
        case let (edited, opened): edited ?? opened
        }
        return launched.map { Self.routine(from: $0, weightUnit: weightUnit) }
    }

    /// Marks the routine opened at `now` and returns it, or nil, storing nothing, if there is
    /// no such routine. Opening counts as using: it moves the routine to the top of the recent
    /// list, and a relaunch opens it.
    public func openRoutine(
        _ id: Routine.ID,
        weightUnit: WeightUnit,
        at now: Date = .now,
    ) throws -> Routine? {
        guard let stored = try stored(id: id) else { return nil }
        stored.openedAt = now
        try modelContext.save()
        return Self.routine(from: stored, weightUnit: weightUnit)
    }

    /// Every saved routine, the latest opened or edited first; a tie by id, so the order is
    /// stable. Sorted here: a sort descriptor can't take the later of two dates.
    public func routinesByRecency(weightUnit: WeightUnit) throws -> [Routine] {
        try modelContext.fetch(FetchDescriptor<StoredRoutine>())
            .map { (recency: max($0.editedAt, $0.openedAt), stored: $0) }
            .sorted {
                $0.recency != $1.recency
                    ? $0.recency > $1.recency
                    : $0.stored.id.uuidString < $1.stored.id.uuidString
            }
            .map { Self.routine(from: $0.stored, weightUnit: weightUnit) }
    }

    /// Saves the routine as it is now, edited at `now`, or deletes it once it is empty.
    public func save(_ routine: Routine, at now: Date = .now) throws {
        let stored = try stored(id: routine.id)
        guard !routine.isEmpty else {
            if let stored {
                modelContext.delete(stored)
                try modelContext.save()
            }
            return
        }
        let target = stored ?? {
            let new = StoredRoutine(id: routine.id)
            modelContext.insert(new)
            return new
        }()
        let oldRows = target.exercises ?? []
        target.name = routine.name
        target.editedAt = now
        let kept = Set(routine.exercises.map(\.id))
        for row in oldRows where !kept.contains(row.id) {
            modelContext.delete(row)
        }
        // Row ids are unique in the app's own writes; keyed leniently against a store that isn't.
        let rowsByID = Dictionary(
            oldRows.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        for (position, item) in routine.exercises.enumerated() {
            let row = rowsByID[item.id] ?? {
                let row = StoredRoutineExercise(
                    id: item.id,
                    exerciseID: item.exercise.id,
                    position: position,
                )
                modelContext.insert(row)
                row.routine = target
                return row
            }()
            if row.position != position {
                row.position = position
            }
            row.write(item.plan)
            if row.supersetID != item.supersetID {
                row.supersetID = item.supersetID
            }
        }
        try modelContext.save()
    }

    #if DEBUG
    /// Empties the store, so a UI test starts from a new routine.
    public func deleteAll() throws {
        for routine in try modelContext.fetch(FetchDescriptor<StoredRoutine>()) {
            modelContext.delete(routine)
        }
        try modelContext.save()
    }
    #endif

    private func latest(by order: SortDescriptor<StoredRoutine>) throws -> StoredRoutine? {
        var descriptor = FetchDescriptor<StoredRoutine>(sortBy: [order])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func stored(id: UUID) throws -> StoredRoutine? {
        var descriptor = FetchDescriptor<StoredRoutine>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// A row whose exercise isn't built in, from a newer version or a renamed slug, is left out
    /// rather than failing the routine. Supersets come back whole, as the rules keep them.
    private static func routine(from stored: StoredRoutine, weightUnit: WeightUnit) -> Routine {
        let rows = (stored.exercises ?? []).sorted { $0.position < $1.position }
        var exercises = rows.compactMap { row -> RoutineExercise? in
            guard let exercise = builtInByID[row.exerciseID] else {
                Logger.storage
                    .error("Skipped a row for unknown exercise \(row.exerciseID, privacy: .public)")
                return nil
            }
            return RoutineExercise(
                id: row.id,
                exercise: exercise,
                plan: row.plan(for: exercise, weightUnit: weightUnit),
                supersetID: row.supersetID,
            )
        }
        // A row left out, or a store written elsewhere, can leave a superset broken or of one.
        exercises.normalizeSupersets()
        return Routine(id: stored.id, name: stored.name, exercises: exercises)
    }
}

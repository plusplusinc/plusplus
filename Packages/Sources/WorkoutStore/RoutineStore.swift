import Foundation
import OSLog
import SwiftData

/// Saves routines and workouts, and finds what the app opens with. Values in, values out: the
/// stored
/// models never leave the actor.
@ModelActor
public actor RoutineStore {
    private static let builtInByID = Dictionary(
        uniqueKeysWithValues: Exercise.builtIn.map { ($0.id, $0) },
    )

    static let schema = Schema(versionedSchema: RoutineMigrationPlan.current)

    public static func open(_ mode: StorageMode) throws -> RoutineStore {
        try RoutineStore(modelContainer: WorkoutStoreContainer.make(
            mode: mode,
            schema: schema,
            migrationPlan: RoutineMigrationPlan.self,
        ))
    }

    /// What the app opens with. A workout in progress opens with its routine, or, if that is
    /// gone, an empty one under its id and name; with more than one, as sync could leave, the
    /// latest started. Otherwise the routine last opened or edited, unless a workout finished
    /// after that, which opens a new routine (nil). Every stored routine has been edited, since
    /// an untouched one is never saved and a cleared one is deleted. A weight never saved reads
    /// as its exercise's default in `weightUnit`.
    public func launch(weightUnit: WeightUnit) throws -> (routine: Routine?, workout: Workout?) {
        let workouts = try modelContext.fetch(FetchDescriptor<StoredWorkout>())
        if let current = workouts.filter({ $0.endedAt == nil }).max(by: Self.startedEarlier) {
            let workout = current.workout
            let routine = try stored(id: workout.routineID)
                .map { Self.routine(from: $0, weightUnit: weightUnit) }
                ?? Routine(id: workout.routineID, name: workout.routineName)
            return (routine, workout)
        }
        // Picked here, as the list sorts, so launch opens the routine the list puts first.
        guard let latest = try modelContext.fetch(FetchDescriptor<StoredRoutine>())
            .min(by: Self.isMoreRecent(_:than:))
        else { return (nil, nil) }
        let lastFinish = workouts.compactMap(\.endedAt).max() ?? .distantPast
        guard lastFinish <= latest.recency else { return (nil, nil) }
        return (Self.routine(from: latest, weightUnit: weightUnit), nil)
    }

    /// Saves the workout as it is now, every field.
    public func save(_ workout: Workout) throws {
        let target = try storedWorkout(id: workout.id) ?? {
            let new = StoredWorkout(id: workout.id)
            modelContext.insert(new)
            return new
        }()
        target.write(workout)
        try modelContext.save()
    }

    /// Deletes the workout, keeping nothing of it; nothing if there is none.
    public func discardWorkout(_ id: Workout.ID) throws {
        guard let stored = try storedWorkout(id: id) else { return }
        modelContext.delete(stored)
        try modelContext.save()
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
    /// stable. Sorted here: a sort descriptor can't take the later of two dates. With them,
    /// when each was last edited, its name or its rows, apart from when it was opened.
    public func routinesByRecency(
        weightUnit: WeightUnit,
    ) throws -> (routines: [Routine], editedAt: [Routine.ID: Date]) {
        let stored = try modelContext.fetch(FetchDescriptor<StoredRoutine>())
            .sorted(by: Self.isMoreRecent(_:than:))
        return (
            stored.map { Self.routine(from: $0, weightUnit: weightUnit) },
            // Ids are unique in the app's own writes; keyed leniently against a store that isn't.
            Dictionary(stored.map { ($0.id, $0.editedAt) }, uniquingKeysWith: max),
        )
    }

    /// Saves the routine as it is now, edited at `now`, or deletes it once it is empty, unless
    /// `keepsEmpty`, as while a workout runs it: the empty routine is stored, and deleted by the
    /// next save without it.
    public func save(_ routine: Routine, at now: Date = .now, keepsEmpty: Bool = false) throws {
        let stored = try stored(id: routine.id)
        guard !routine.isEmpty || keepsEmpty else {
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
    /// Empties the store, so a UI test starts from a new routine and no workout.
    public func deleteAll() throws {
        for routine in try modelContext.fetch(FetchDescriptor<StoredRoutine>()) {
            modelContext.delete(routine)
        }
        for workout in try modelContext.fetch(FetchDescriptor<StoredWorkout>()) {
            modelContext.delete(workout)
        }
        try modelContext.save()
    }
    #endif

    /// Recency, the later of a routine's last edit and last open; a tie by id, so the order is
    /// stable and launch opens the routine listed first.
    private static func isMoreRecent(_ one: StoredRoutine, than other: StoredRoutine) -> Bool {
        let (oneRecency, otherRecency) = (one.recency, other.recency)
        return oneRecency != otherRecency ? oneRecency > otherRecency : one.id < other.id
    }

    /// A tie by id, so the same one is picked every launch.
    private static func startedEarlier(_ one: StoredWorkout, than other: StoredWorkout) -> Bool {
        one.startedAt != other.startedAt ? one.startedAt < other.startedAt : one.id < other.id
    }

    private func storedWorkout(id: UUID) throws -> StoredWorkout? {
        var descriptor = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })
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

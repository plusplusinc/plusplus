import Foundation
import OSLog
import SwiftData

/// Saves routines and workouts, and finds what the app opens with. Values in, values out: the
/// stored models never leave the actor.
@ModelActor
public actor RoutineStore {
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
        var inProgress = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.id)],
        )
        inProgress.fetchLimit = 1
        if let current = try modelContext.fetch(inProgress).first {
            let workout = current.workout
            let exercises = try exercises()
            let routine = try stored(id: workout.routineID)
                .map { Self.routine(from: $0, exercises: exercises, weightUnit: weightUnit) }
                ?? Routine(id: workout.routineID, name: workout.routineName)
            return (routine, workout)
        }
        // Picked here, as the list sorts, so launch opens the routine the list puts first.
        guard let latest = try modelContext.fetch(FetchDescriptor<StoredRoutine>())
            .min(by: Self.isMoreRecent(_:than:))
        else { return (nil, nil) }
        var finished = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)],
        )
        finished.fetchLimit = 1
        let lastFinish = try modelContext.fetch(finished).first?.endedAt ?? .distantPast
        guard lastFinish <= latest.recency else { return (nil, nil) }
        return try (Self.routine(from: latest, exercises: exercises(), weightUnit: weightUnit), nil)
    }

    /// Saves the workout as it is now, every field. Once it has ended, its routine, if cleared
    /// to nothing while it ran, goes in the same save.
    public func save(_ workout: Workout) throws {
        let target = try storedWorkout(id: workout.id) ?? {
            let new = StoredWorkout(id: workout.id)
            modelContext.insert(new)
            return new
        }()
        target.write(workout)
        writeSets(workout.sets, of: target)
        if !workout.isInProgress {
            try deleteIfCleared(routineID: workout.routineID)
        }
        try modelContext.save()
    }

    /// Diffs the workout's stored sets against `sets` by id: a set gone is deleted, a new one
    /// inserted, and each written at its place in the order logged. A stored set this build
    /// can't read, never in `sets`, is kept rather than taken for one gone.
    private func writeSets(_ sets: [LoggedSet], of workout: StoredWorkout) {
        let old = workout.sets ?? []
        let kept = Set(sets.map(\.id))
        for set in old where !kept.contains(set.id) && set.isReadable {
            modelContext.delete(set)
        }
        // Set ids are unique in the app's own writes; keyed leniently against a store that isn't.
        let byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (position, set) in sets.enumerated() {
            let stored = byID[set.id] ?? {
                let new = StoredSet(id: set.id)
                modelContext.insert(new)
                new.workout = workout
                return new
            }()
            stored.write(set, position: position)
        }
    }

    /// Deletes the workout, keeping nothing of it, its sets with it, and its routine if cleared to
    /// nothing while it ran, in one save; nothing if there is none.
    public func discardWorkout(_ id: Workout.ID) throws {
        guard let stored = try storedWorkout(id: id) else { return }
        if let routineID = stored.routineID {
            try deleteIfCleared(routineID: routineID)
        }
        modelContext.delete(stored)
        try modelContext.save()
    }

    /// A routine cleared to nothing is kept only while its workout runs; ending the workout
    /// deletes it in the same save, so no empty routine outlives a workout cut short between
    /// two writes.
    private func deleteIfCleared(routineID: UUID) throws {
        guard let routine = try stored(id: routineID),
              routine.name.isEmpty, routine.exercises?.isEmpty ?? true
        else { return }
        modelContext.delete(routine)
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
        return try Self.routine(from: stored, exercises: exercises(), weightUnit: weightUnit)
    }

    /// Every saved routine, the latest opened or edited first; a tie by id, so the order is
    /// stable. Sorted here: a sort descriptor can't take the later of two dates.
    public func routinesByRecency(weightUnit: WeightUnit) throws -> [Routine] {
        let exercises = try exercises()
        return try modelContext.fetch(FetchDescriptor<StoredRoutine>())
            .sorted(by: Self.isMoreRecent(_:than:))
            .map { Self.routine(from: $0, exercises: exercises, weightUnit: weightUnit) }
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
            row.write(roundRest: item.roundRest)
            if row.supersetID != item.supersetID {
                row.supersetID = item.supersetID
            }
        }
        try modelContext.save()
    }

    /// Every exercise there is to pick: the built-ins and each created one this build can read.
    /// One it can't, from a newer version, is kept in the store, never deleted.
    public func exercises() throws -> ExerciseList {
        try ExerciseList(created: modelContext.fetch(FetchDescriptor<StoredExercise>())
            .compactMap(\.created))
    }

    /// Stores a created exercise, or updates the one with its id.
    public func save(_ created: CreatedExercise) throws {
        let id = created.id
        var descriptor = FetchDescriptor<StoredExercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let target = try modelContext.fetch(descriptor).first ?? {
            let new = StoredExercise(id: id)
            modelContext.insert(new)
            return new
        }()
        target.write(created)
        try modelContext.save()
    }

    #if DEBUG
    /// Empties the store, so a UI test starts from a new routine, no workout, and no exercise
    /// anyone created.
    public func deleteAll() throws {
        for exercise in try modelContext.fetch(FetchDescriptor<StoredExercise>()) {
            modelContext.delete(exercise)
        }
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

    /// A row whose exercise isn't in `list`, from a newer version, a renamed slug, or a created
    /// exercise this build can't read, is left out rather than failing the routine. Supersets
    /// come back whole, as the rules keep them.
    static func routine(
        from stored: StoredRoutine,
        exercises list: ExerciseList,
        weightUnit: WeightUnit,
    ) -> Routine {
        let rows = (stored.exercises ?? []).sorted { $0.position < $1.position }
        var exercises = rows.compactMap { row -> RoutineExercise? in
            guard let exercise = list.exercise(id: row.exerciseID) else {
                Logger.storage
                    .error("Skipped a row for unknown exercise \(row.exerciseID, privacy: .public)")
                return nil
            }
            return RoutineExercise(
                id: row.id,
                exercise: exercise,
                plan: row.plan(for: exercise, weightUnit: weightUnit),
                supersetID: row.supersetID,
                roundRest: row.storedRoundRest,
            )
        }
        // A row left out, or a store written elsewhere, can leave a superset broken or of one.
        exercises.normalizeSupersets()
        return Routine(id: stored.id, name: stored.name, exercises: exercises)
    }
}

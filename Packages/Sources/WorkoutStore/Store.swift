import Foundation
import OSLog
import SwiftData

/// Saves workouts and logged workouts, and finds what the app opens with. Values in, values out:
/// the stored models never leave the actor.
@ModelActor
public actor Store {
    static let schema = Schema(versionedSchema: StoreMigrationPlan.current)

    public static func open(_ mode: StorageMode) throws -> Store {
        try Store(modelContainer: WorkoutStoreContainer.make(
            mode: mode,
            schema: schema,
            migrationPlan: StoreMigrationPlan.self,
        ))
    }

    /// What the app opens with (`Launch`). A logged workout in progress opens with its workout,
    /// or, if that is gone, an empty one under its id and name; with more than one, as sync could
    /// leave, the latest started. Otherwise the workout last opened or edited, unless a logged
    /// workout finished after that, which opens the Workouts list; with no saved workout, a new
    /// one. Every stored workout has been edited, since an untouched one is never saved and a
    /// cleared one is deleted. A weight never saved reads as its exercise's default in
    /// `weightUnit`.
    public func launch(weightUnit: WeightUnit) throws -> Launch {
        var inProgress = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.id)],
        )
        inProgress.fetchLimit = 1
        if let current = try modelContext.fetch(inProgress).first {
            let loggedWorkout = current.loggedWorkout
            let exercises = try exercises()
            let workout = try stored(id: loggedWorkout.workoutID)
                .map { Self.workout(from: $0, exercises: exercises, weightUnit: weightUnit) }
                ?? Workout(id: loggedWorkout.workoutID, name: loggedWorkout.workoutName)
            return .inProgress(workout, loggedWorkout)
        }
        // Picked here, as the list sorts, so launch opens the workout the list puts first.
        guard let latest = try modelContext.fetch(FetchDescriptor<StoredRoutine>())
            .min(by: Self.isMoreRecent(_:than:))
        else { return .newWorkout }
        var finished = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)],
        )
        finished.fetchLimit = 1
        let lastFinish = try modelContext.fetch(finished).first?.endedAt ?? .distantPast
        guard lastFinish <= latest.recency else { return .workouts }
        return try .workout(Self.workout(
            from: latest,
            exercises: exercises(),
            weightUnit: weightUnit,
        ))
    }

    /// Saves the logged workout as it is now, every field. Once it has ended, its workout, if
    /// cleared to nothing while it ran, goes in the same save.
    public func save(_ loggedWorkout: LoggedWorkout) throws {
        let target = try storedLoggedWorkout(id: loggedWorkout.id) ?? {
            let new = StoredWorkout(id: loggedWorkout.id)
            modelContext.insert(new)
            return new
        }()
        target.write(loggedWorkout)
        writeSets(loggedWorkout.sets, of: target)
        if !loggedWorkout.isInProgress {
            try deleteIfCleared(workoutID: loggedWorkout.workoutID)
        }
        try modelContext.save()
    }

    /// Diffs the logged workout's stored sets against `sets` by id: a set gone is deleted, a
    /// new one inserted, and each written at its place in the order logged. A stored set this build
    /// can't read, never in `sets`, is kept rather than taken for one gone.
    private func writeSets(_ sets: [LoggedSet], of loggedWorkout: StoredWorkout) {
        let old = loggedWorkout.sets ?? []
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
                new.workout = loggedWorkout
                return new
            }()
            stored.write(set, position: position)
        }
    }

    /// Every finished logged workout, the latest finish first, a tie by id. All of them, not a
    /// window: an opened logged workout compares with the time before, however long ago.
    public func finishedLoggedWorkouts() throws -> [LoggedWorkout] {
        let finished = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse), SortDescriptor(\.id)],
        )
        return try modelContext.fetch(finished).map(\.loggedWorkout)
    }

    /// Deletes the logged workout, keeping nothing of it, its sets with it, and its workout if
    /// cleared to nothing while it ran, in one save; nothing if there is none. A discard that
    /// doesn't save is undone, all of it (`saveOrRollback()`).
    public func discardLoggedWorkout(_ id: LoggedWorkout.ID) throws {
        guard let stored = try storedLoggedWorkout(id: id) else { return }
        if let workoutID = stored.routineID {
            try deleteIfCleared(workoutID: workoutID)
        }
        modelContext.delete(stored)
        try saveOrRollback()
    }

    /// Deletes a finished logged workout and its sets; nothing if there is none, or if it is still
    /// in progress, which only Discard ends without keeping. Its workout stays, as it holds no
    /// link to it. A delete that doesn't save is undone (`saveOrRollback()`).
    public func deleteLoggedWorkout(_ id: LoggedWorkout.ID) throws {
        guard let stored = try storedLoggedWorkout(id: id), stored.endedAt != nil else { return }
        modelContext.delete(stored)
        try saveOrRollback()
    }

    /// Saves the context, or, when the save fails, undoes every change since the last save and
    /// rethrows: reads still return what a delete would have deleted, and no later save of
    /// something else lands it unasked. Called by `deleteWorkout`, `discardLoggedWorkout`,
    /// `deleteLoggedWorkout`, and `deleteExercise`; the store's other writes save plainly.
    func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// A workout cleared to nothing is kept only while it is in progress; ending the logged
    /// workout deletes it in the same save, so no empty workout outlives one cut short between
    /// two writes.
    private func deleteIfCleared(workoutID: UUID) throws {
        guard let workout = try stored(id: workoutID),
              workout.name.isEmpty, workout.exercises?.isEmpty ?? true
        else { return }
        modelContext.delete(workout)
    }

    /// Deletes the workout and its rows; nothing if there is none. Its logged workouts hold its id
    /// and name, not a relationship, so they stay stored. A delete that doesn't save is undone
    /// (`saveOrRollback()`).
    public func deleteWorkout(_ id: Workout.ID) throws {
        guard let workout = try stored(id: id) else { return }
        modelContext.delete(workout)
        try saveOrRollback()
    }

    /// Marks the workout opened at `now` and returns it, or nil, storing nothing, if there is
    /// no such workout. Opening counts as using: it moves the workout to the top of the recent
    /// list, and a relaunch opens it.
    public func openWorkout(
        _ id: Workout.ID,
        weightUnit: WeightUnit,
        at now: Date = .now,
    ) throws -> Workout? {
        guard let stored = try stored(id: id) else { return nil }
        stored.openedAt = now
        try modelContext.save()
        return try Self.workout(from: stored, exercises: exercises(), weightUnit: weightUnit)
    }

    /// Every saved workout, the latest opened or edited first; a tie by id, so the order is
    /// stable. Sorted here: a sort descriptor can't take the later of two dates.
    public func workoutsByRecency(weightUnit: WeightUnit) throws -> [Workout] {
        let exercises = try exercises()
        return try modelContext.fetch(FetchDescriptor<StoredRoutine>())
            .sorted(by: Self.isMoreRecent(_:than:))
            .map { Self.workout(from: $0, exercises: exercises, weightUnit: weightUnit) }
    }

    /// Saves the workout as it is now, edited at `now`, or deletes it once it is empty, unless
    /// `keepsEmpty`, as while it is in progress: the empty workout is stored, and deleted by the
    /// next save without it.
    public func save(_ workout: Workout, at now: Date = .now, keepsEmpty: Bool = false) throws {
        let stored = try stored(id: workout.id)
        guard !workout.isEmpty || keepsEmpty else {
            if let stored {
                modelContext.delete(stored)
                try modelContext.save()
            }
            return
        }
        let target = stored ?? {
            let new = StoredRoutine(id: workout.id)
            modelContext.insert(new)
            return new
        }()
        target.name = workout.name
        target.editedAt = now
        try writeRows(workout.exercises, of: target)
        try modelContext.save()
    }

    /// Every exercise there is to pick: the built-ins, as customized, and each created one this
    /// build can read. One it can't, from a newer version, is kept in the store, never deleted.
    /// With two customizations of one built-in, as sync could leave, the latest edited counts.
    public func exercises() throws -> ExerciseList {
        let customizations = try modelContext.fetch(FetchDescriptor<StoredCustomization>(
            sortBy: [SortDescriptor(\.editedAt, order: .reverse)],
        ))
        return try ExerciseList(
            created: modelContext.fetch(FetchDescriptor<StoredExercise>()).compactMap(\.created),
            customizations: customizations.map(\.customization),
        )
    }

    /// Stores a created exercise, or updates the one with its id.
    public func save(_ created: CreatedExercise) throws {
        let id = created.id
        var descriptor = FetchDescriptor<StoredExercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let stored = try modelContext.fetch(descriptor).first
        try keepLoggedNames(of: id, named: stored?.name, renamedTo: created.name)
        let target = stored ?? {
            let new = StoredExercise(id: id)
            modelContext.insert(new)
            return new
        }()
        target.write(created)
        try modelContext.save()
    }

    #if DEBUG
    /// Empties the store, so a UI test starts from a new workout, no logged workout, and no
    /// exercise anyone created or customized.
    public func deleteAll() throws {
        for exercise in try modelContext.fetch(FetchDescriptor<StoredExercise>()) {
            modelContext.delete(exercise)
        }
        for customization in try modelContext.fetch(FetchDescriptor<StoredCustomization>()) {
            modelContext.delete(customization)
        }
        for workout in try modelContext.fetch(FetchDescriptor<StoredRoutine>()) {
            modelContext.delete(workout)
        }
        for loggedWorkout in try modelContext.fetch(FetchDescriptor<StoredWorkout>()) {
            modelContext.delete(loggedWorkout)
        }
        try modelContext.save()
    }
    #endif

    /// Recency, the later of a workout's last edit and last open; a tie by id, so the order is
    /// stable and launch opens the workout listed first.
    private static func isMoreRecent(_ one: StoredRoutine, than other: StoredRoutine) -> Bool {
        let (oneRecency, otherRecency) = (one.recency, other.recency)
        return oneRecency != otherRecency ? oneRecency > otherRecency : one.id < other.id
    }

    private func storedLoggedWorkout(id: UUID) throws -> StoredWorkout? {
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
    /// exercise this build can't read, is left out rather than failing the workout, and kept in
    /// the store by its saves (`writeRows`). Supersets
    /// come back whole, as the rules keep them.
    static func workout(
        from stored: StoredRoutine,
        exercises list: ExerciseList,
        weightUnit: WeightUnit,
    ) -> Workout {
        let rows = (stored.exercises ?? []).sorted { $0.position < $1.position }
        var exercises = rows.compactMap { row -> WorkoutExercise? in
            guard let exercise = list.exercise(id: row.exerciseID) else {
                Logger.storage
                    .error("Skipped a row for unknown exercise \(row.exerciseID, privacy: .public)")
                return nil
            }
            return WorkoutExercise(
                id: row.id,
                exercise: exercise,
                plan: row.plan(for: exercise, weightUnit: weightUnit),
                supersetID: row.supersetID,
                roundRest: row.storedRoundRest,
            )
        }
        // A row left out, or a store written elsewhere, can leave a superset broken or of one.
        exercises.normalizeSupersets()
        return Workout(id: stored.id, name: stored.name, exercises: exercises)
    }
}

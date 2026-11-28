import Foundation
import SwiftData
@testable import WorkoutStore

/// A V14 store on disk, as a phone holds one, and every stored value in it as lines of text, so
/// a row dropped, a field lost, or a link cut makes two stores' lines differ. `Fixtures/V14/`
/// holds one this wrote with the code at d8d42daf, before any stored name changed; the tests
/// write others like it.
enum StoreRenameFixture {
    typealias OldWorkout = RoutineSchemaV7.StoredRoutine
    typealias OldRow = RoutineSchemaV7.StoredRoutineExercise
    typealias OldSession = RoutineSchemaV14.StoredWorkout
    typealias OldSet = RoutineSchemaV14.StoredSet

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreRename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Writes a V14 store and returns its lines.
    @discardableResult
    static func writeV14(at url: URL, sessions: Int = 2, setsEach: Int = 3) throws -> [String] {
        let schema = Schema(versionedSchema: RoutineSchemaV14.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(container)
        let workouts = insertWorkouts(in: context)
        insertExercises(in: context)
        let rows = workouts.flatMap { $0.exercises ?? [] }.sorted { $0.position < $1.position }
        for index in 0 ..< sessions {
            let workout = workouts[index % workouts.count]
            let session = OldSession(id: UUID())
            session.routineID = workout.id
            session.routineName = workout.name
            session.startedAt = at(Double(index) * 10000)
            session.endedAt = at(Double(index) * 10000 + 3600)
            session.healthActivity = "traditionalStrengthTraining"
            session.healthWorkoutID = index.isMultiple(of: 2) ? UUID() : nil
            context.insert(session)
            insertSets(setsEach, in: session, rows: rows, context: context)
        }
        insertInProgress(on: workouts[0], in: context)
        try context.save()
        return try lines(old: context)
    }

    /// Three workouts: one with a superset of two and a plain row, one plain, one unnamed.
    private static func insertWorkouts(in context: ModelContext) -> [OldWorkout] {
        let shapes: [(String, [String])] = [
            ("Upper", ["push-up", "pull-up", "dumbbell-row"]),
            ("Stretch", ["pigeon-stretch"]),
            ("", ["pull-up", "push-up"]),
        ]
        return shapes.enumerated().map { index, shape in
            let workout = OldWorkout(id: UUID())
            workout.name = shape.0
            workout.editedAt = at(Double(index))
            workout.openedAt = at(Double(index) + 0.5)
            context.insert(workout)
            let supersetID = UUID()
            for (position, exerciseID) in shape.1.enumerated() {
                let row = OldRow(id: UUID(), exerciseID: exerciseID, position: position)
                row.sets = 3 + position
                row.reps = position == 1 ? nil : 8
                row.seconds = position == 1 ? 45 : nil
                row.weight = 22.5
                row.weightUnit = "kg"
                row.rest = 90
                row.isRestAuto = position.isMultiple(of: 2)
                if index == 0, position < 2 {
                    row.supersetID = supersetID
                    row.roundRest = 120
                    row.isRoundRestAuto = false
                }
                context.insert(row)
                row.routine = workout
            }
            return workout
        }
    }

    /// Two created exercises, one of several groups, and a customized built-in.
    private static func insertExercises(in context: ModelContext) {
        for (index, groups) in ["back", "chest,shoulders"].enumerated() {
            let exercise = RoutineSchemaV8.StoredExercise(id: "created-\(index)")
            exercise.name = "Created \(index)"
            exercise.muscleGroup = groups
            exercise.equipment = "rings"
            exercise.measure = index == 0 ? "reps" : "time"
            exercise.isPerSide = index == 1
            exercise.createdAt = at(Double(index) + 50)
            context.insert(exercise)
        }
        let customized = RoutineSchemaV10.StoredCustomization(exerciseID: "push-up")
        customized.changed = "name,muscleGroups"
        customized.name = "Press-up"
        customized.muscleGroups = "chest"
        customized.editedAt = at(60)
        context.insert(customized)
    }

    static func insertSets(
        _ count: Int,
        in session: OldSession?,
        rows: [OldRow],
        context: ModelContext,
    ) {
        for position in 0 ..< count {
            let row = rows[position % rows.count]
            let set = OldSet(id: UUID())
            set.rowID = row.id
            set.exerciseID = row.exerciseID
            set.exerciseName = position.isMultiple(of: 3) ? nil : "Name \(position)"
            set.position = position
            set.round = position / rows.count + 1
            set.side = position.isMultiple(of: 2) ? "left" : nil
            set.reps = 8
            set.weight = 20
            set.weightUnit = "kg"
            set.plannedReps = 8
            set.plannedWeight = 22.5
            set.plannedWeightUnit = "kg"
            set.loggedAt = (session?.startedAt ?? .distantPast)
                .addingTimeInterval(Double(position) * 60)
            set.clockWhenLogged = Double(position) * 60
            set.restAdjustment = position.isMultiple(of: 2) ? 15 : -15
            set.timeAdded = 15
            set.restSkippedAt = position.isMultiple(of: 4) ? Double(position) * 60 + 30 : nil
            context.insert(set)
            set.workout = session
        }
    }

    /// The session in progress: paused, after a pause resumed, with a timed set's count under way.
    private static func insertInProgress(on workout: OldWorkout, in context: ModelContext) {
        let session = OldSession(id: UUID())
        session.routineID = workout.id
        session.routineName = workout.name
        session.startedAt = at(900_000)
        session.pausedAt = at(900_600)
        session.pausedSeconds = 30
        session.pauseTimes = [at(900_100), at(900_130)]
        let row = (workout.exercises ?? []).first { $0.position == 1 }
        session.countRowID = row?.id
        session.countRound = 2
        session.countSide = "right"
        session.countStartClock = 400.25
        session.countAdded = 15
        context.insert(session)
        insertSets(2, in: session, rows: workout.exercises ?? [], context: context)
    }
}

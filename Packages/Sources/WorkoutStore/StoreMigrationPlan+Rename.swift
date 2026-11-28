import Foundation
import OSLog
import SwiftData

/// The moves that rename the stored models, each run in the stage before the one that drops or
/// reshapes the old model, while its rows are still there to read. Each inserts one new row per
/// old row with every field, links each child to the new row made from its old parent, by the
/// old parent's identity, not its `id`, which nothing makes unique, deletes the old rows, and
/// saves once: a move is done whole or not at all, and run again finds nothing to move.
extension StoreMigrationPlan {
    /// In a V15 store: every `StoredWorkout`, a session, and its `StoredSet`s, under their new
    /// names, so the next stage, which gives `StoredWorkout` to the workout, finds it empty.
    static func moveSessions(in context: ModelContext) throws {
        typealias Old = RoutineSchemaV14
        typealias New = StoreSchemaV15
        let oldSessions = try context.fetch(FetchDescriptor<Old.StoredWorkout>())
        var moved: [PersistentIdentifier: New.StoredWorkoutSession] = [:]
        for old in oldSessions {
            let new = New.StoredWorkoutSession(id: old.id)
            new.workoutID = old.routineID
            new.workoutName = old.routineName
            new.startedAt = old.startedAt
            new.pausedAt = old.pausedAt
            new.pausedSeconds = old.pausedSeconds
            new.endedAt = old.endedAt
            new.countRowID = old.countRowID
            new.countRound = old.countRound
            new.countSide = old.countSide
            new.countStartClock = old.countStartClock
            new.countAdded = old.countAdded
            new.pauseTimes = old.pauseTimes
            new.healthActivity = old.healthActivity
            new.healthWorkoutID = old.healthWorkoutID
            context.insert(new)
            moved[old.persistentModelID] = new
        }
        let oldSets = try context.fetch(FetchDescriptor<Old.StoredSet>())
        for old in oldSets {
            let new = New.StoredLoggedSet(id: old.id)
            new.rowID = old.rowID
            new.exerciseID = old.exerciseID
            new.exerciseName = old.exerciseName
            new.position = old.position
            new.round = old.round
            new.side = old.side
            new.reps = old.reps
            new.seconds = old.seconds
            new.weight = old.weight
            new.weightUnit = old.weightUnit
            new.plannedReps = old.plannedReps
            new.plannedSeconds = old.plannedSeconds
            new.plannedWeight = old.plannedWeight
            new.plannedWeightUnit = old.plannedWeightUnit
            new.loggedAt = old.loggedAt
            new.clockWhenLogged = old.clockWhenLogged
            new.restAdjustment = old.restAdjustment
            new.timeAdded = old.timeAdded
            new.restSkippedAt = old.restSkippedAt
            context.insert(new)
            new.workoutSession = old.workout.flatMap { moved[$0.persistentModelID] }
        }
        for old in oldSets {
            context.delete(old)
        }
        for old in oldSessions {
            context.delete(old)
        }
        try context.save()
        Logger.storage.info(
            "Moved \(oldSessions.count) sessions and \(oldSets.count) sets to their new names",
        )
    }
}

import CoreData
import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// One line per stored row, every field in order, and the id of the row it belongs to; the
/// same text under the old names and the new, sorted, so equal lists mean nothing changed.
extension StoreRenameFixture {
    /// Every value, a date as its exact seconds.
    static func text(_ kind: String, _ values: [Any?]) -> String {
        let fields = values.map { value -> String in
            switch value {
            case nil: "nil"
            case let date as Date: "\(date.timeIntervalSinceReferenceDate)"
            case let dates as [Date]: dates.map { "\($0.timeIntervalSinceReferenceDate)" }
                .joined(separator: ",")
            case let value?: "\(value)"
            }
        }
        return ([kind] + fields).joined(separator: "|")
    }

    /// The store's lines under V14's names.
    static func lines(old context: ModelContext) throws -> [String] {
        let workouts = try context.fetch(FetchDescriptor<OldWorkout>()).map {
            text("workout", [$0.id, $0.name, $0.editedAt, $0.openedAt])
        }
        let rows = try context.fetch(FetchDescriptor<OldRow>()).map {
            text("row", [
                $0.id, $0.routine?.id, $0.exerciseID, $0.position, $0.sets, $0.reps,
                $0.seconds, $0.weight, $0.weightUnit, $0.supersetID, $0.rest, $0.isRestAuto,
                $0.roundRest, $0.isRoundRestAuto,
            ])
        }
        let sessions = try context.fetch(FetchDescriptor<OldSession>()).map {
            text("session", [
                $0.id, $0.routineID, $0.routineName, $0.startedAt, $0.pausedAt,
                $0.pausedSeconds, $0.endedAt, $0.countRowID, $0.countRound, $0.countSide,
                $0.countStartClock, $0.countAdded, $0.pauseTimes, $0.healthActivity,
                $0.healthWorkoutID,
            ])
        }
        let sets = try context.fetch(FetchDescriptor<OldSet>()).map {
            text("set", [
                $0.id, $0.workout?.id, $0.rowID, $0.exerciseID, $0.exerciseName,
                $0.position, $0.round, $0.side, $0.reps, $0.seconds, $0.weight, $0.weightUnit,
                $0.plannedReps, $0.plannedSeconds, $0.plannedWeight, $0.plannedWeightUnit,
                $0.loggedAt, $0.clockWhenLogged, $0.restAdjustment, $0.timeAdded,
                $0.restSkippedAt,
            ])
        }
        let exercises = try context.fetch(FetchDescriptor<RoutineSchemaV8.StoredExercise>()).map {
            text("exercise", [
                $0.id, $0.name, $0.muscleGroup, $0.equipment, $0.measure, $0.isPerSide,
                $0.createdAt,
            ])
        }
        return try (workouts + rows + sessions + sets + exercises + customizations(in: context))
            .sorted()
    }

    /// The store's lines under today's names, in the same text as V14's.
    static func lines(current context: ModelContext) throws -> [String] {
        let workouts = try context.fetch(FetchDescriptor<StoredWorkout>()).map {
            text("workout", [$0.id, $0.name, $0.editedAt, $0.openedAt])
        }
        let rows = try context.fetch(FetchDescriptor<StoredWorkoutExercise>()).map {
            text("row", [
                $0.id, $0.workout?.id, $0.exerciseID, $0.position, $0.sets, $0.reps,
                $0.seconds, $0.weight, $0.weightUnit, $0.supersetID, $0.rest, $0.isRestAuto,
                $0.roundRest, $0.isRoundRestAuto,
            ])
        }
        let sessions = try context.fetch(FetchDescriptor<StoredWorkoutSession>()).map {
            text("session", [
                $0.id, $0.workoutID, $0.workoutName, $0.startedAt, $0.pausedAt,
                $0.pausedSeconds, $0.endedAt, $0.countRowID, $0.countRound, $0.countSide,
                $0.countStartClock, $0.countAdded, $0.pauseTimes, $0.healthActivity,
                $0.healthWorkoutID,
            ])
        }
        let sets = try context.fetch(FetchDescriptor<StoredLoggedSet>()).map {
            text("set", [
                $0.id, $0.workoutSession?.id, $0.rowID, $0.exerciseID, $0.exerciseName,
                $0.position, $0.round, $0.side, $0.reps, $0.seconds, $0.weight, $0.weightUnit,
                $0.plannedReps, $0.plannedSeconds, $0.plannedWeight, $0.plannedWeightUnit,
                $0.loggedAt, $0.clockWhenLogged, $0.restAdjustment, $0.timeAdded,
                $0.restSkippedAt,
            ])
        }
        let exercises = try context.fetch(FetchDescriptor<StoredExercise>()).map {
            text("exercise", [
                $0.id, $0.name, $0.muscleGroups, $0.equipment, $0.measure, $0.isPerSide,
                $0.createdAt,
            ])
        }
        return try (workouts + rows + sessions + sets + exercises + customizations(in: context))
            .sorted()
    }

    /// Unchanged by the rename, so one reader serves both.
    static func customizations(in context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<RoutineSchemaV10.StoredCustomization>()).map {
            text("customization", [
                $0.exerciseID, $0.changed, $0.name, $0.muscleGroups, $0.equipment, $0.measure,
                $0.isPerSide, $0.editedAt,
            ])
        }
    }

    /// How many lines of each kind, as kind to count.
    static func counts(_ lines: [String]) -> [String: Int] {
        Dictionary(grouping: lines) { String($0.prefix { $0 != "|" }) }.mapValues(\.count)
    }

    /// The entities a store on disk holds, read from its metadata without opening it, which
    /// would migrate it.
    static func storedEntities(at url: URL) throws -> [String] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: url,
        )
        let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] ?? [:]
        return hashes.keys.sorted()
    }

    /// A copy of the committed V14 store in a new folder, and the lines it was written with.
    static func copyCommitted() throws -> (url: URL, lines: [String]) {
        let source = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appending(path: "V14")
        let folder = try folder()
        for name in try FileManager.default.contentsOfDirectory(atPath: source.path())
            where name.hasPrefix("PlusPlus.store")
        {
            try FileManager.default.copyItem(
                at: source.appending(path: name),
                to: folder.appending(path: name),
            )
        }
        let lines = try String(contentsOf: source.appending(path: "lines.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        return (folder.appending(path: "PlusPlus.store"), lines)
    }
}

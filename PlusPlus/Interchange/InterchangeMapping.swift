import Foundation
import SwiftData
import PlusPlusKit

/// Bridges SwiftData models and the interchange DTOs (PlusPlusKit). Lives in
/// the app because it needs the models; the format itself is app-agnostic.
enum InterchangeMapping {
    struct ImportSummary: Equatable {
        var exercisesCreated = 0
        var exercisesUpdated = 0
        var routinesCreated = 0
        var routinesReplaced = 0
        var sessionsAdded = 0
        var sessionsSkipped = 0
    }

    enum ImportError: Error {
        case invalidBundle([ValidationIssue])
    }

    // MARK: - Export

    static func exportBundle(context: ModelContext, units: WeightUnit? = nil) throws -> ExportBundle {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil })
        )
        return ExportBundle(
            units: units,
            // Built-ins ship with every install; only export ones the user
            // has annotated so imports stay meaningful.
            exercises: exercises
                .filter { !$0.isBuiltIn || $0.notes != nil || $0.videoURL != nil }
                .map(makeDTO),
            routines: routines.map(makeDTO),
            sessions: sessions.map(makeDTO)
        )
    }

    static func makeDTO(_ exercise: Exercise) -> ExerciseDTO {
        ExerciseDTO(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup,
            exerciseType: exercise.exerciseType,
            equipment: exercise.equipment.map(\.name),
            notes: exercise.notes,
            videoURL: exercise.videoURL,
            isBuiltIn: exercise.isBuiltIn
        )
    }

    static func makeDTO(_ routine: Routine) -> RoutineDTO {
        RoutineDTO(
            name: routine.name,
            restSeconds: routine.restSeconds,
            notes: routine.notes,
            groups: routine.sortedGroups.map { group in
                .init(
                    sets: group.sets,
                    exercises: group.sortedExercises.compactMap { entry in
                        guard let exercise = entry.exercise else { return nil }
                        return .init(
                            exercise: exercise.name,
                            weight: entry.weight,
                            reps: entry.reps,
                            repsUpper: entry.repsUpper,
                            durationSeconds: entry.durationSeconds
                        )
                    }
                )
            }
        )
    }

    static func makeDTO(_ session: WorkoutSession) -> SessionDTO {
        SessionDTO(
            routineName: session.routineName,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            restSeconds: session.restSeconds,
            sets: session.sortedSetLogs.map { log in
                .init(
                    order: log.order,
                    groupIndex: log.groupIndex,
                    setNumber: log.setNumber,
                    exerciseName: log.exerciseName,
                    exerciseType: log.exerciseType,
                    targetWeight: log.targetWeight,
                    targetRepsLower: log.targetRepsLower,
                    targetRepsUpper: log.targetRepsUpper,
                    targetDuration: log.targetDuration,
                    actualWeight: log.actualWeight,
                    actualReps: log.actualReps,
                    actualDuration: log.actualDuration,
                    completedAt: log.completedAt
                )
            }
        )
    }

    // MARK: - Import

    /// Import policy (documented in docs/PLATFORM.md): exercises upsert by
    /// case-insensitive name; routines replace-or-create by name; sessions
    /// are append-only — a session matching an existing (routineName,
    /// startedAt) is skipped, so history is never overwritten.
    @discardableResult
    static func importBundle(_ bundle: ExportBundle, context: ModelContext) throws -> ImportSummary {
        let issues = InterchangeValidator.validate(bundle)
        guard issues.isEmpty else {
            throw ImportError.invalidBundle(issues)
        }

        var summary = ImportSummary()

        var equipmentByName = try dictionaryByLowercasedName(
            context.fetch(FetchDescriptor<Equipment>()), name: \.name
        )
        var exercisesByName = try dictionaryByLowercasedName(
            context.fetch(FetchDescriptor<Exercise>()), name: \.name
        )

        for dto in bundle.exercises {
            let key = dto.name.lowercased()
            if let existing = exercisesByName[key] {
                existing.muscleGroup = dto.muscleGroup
                existing.exerciseType = dto.exerciseType
                existing.notes = dto.notes
                existing.videoURL = dto.videoURL
                existing.equipment = dto.equipment.map { resolveEquipment($0, in: &equipmentByName, context: context) }
                summary.exercisesUpdated += 1
            } else {
                let exercise = Exercise(
                    name: dto.name,
                    muscleGroup: dto.muscleGroup,
                    equipment: dto.equipment.map { resolveEquipment($0, in: &equipmentByName, context: context) },
                    exerciseType: dto.exerciseType,
                    isBuiltIn: false,
                    notes: dto.notes,
                    videoURL: dto.videoURL
                )
                context.insert(exercise)
                exercisesByName[key] = exercise
                summary.exercisesCreated += 1
            }
        }

        let existingRoutines = try context.fetch(FetchDescriptor<Routine>())
        var routineOrder = existingRoutines.count
        for dto in bundle.routines {
            let target: Routine
            if let existing = existingRoutines.first(where: { $0.name.lowercased() == dto.name.lowercased() }) {
                for group in existing.groups {
                    context.delete(group)
                }
                target = existing
                summary.routinesReplaced += 1
            } else {
                target = Routine(name: dto.name, order: routineOrder)
                routineOrder += 1
                context.insert(target)
                summary.routinesCreated += 1
            }
            target.restSeconds = dto.restSeconds
            target.notes = dto.notes

            for groupDTO in dto.groups {
                var group: ExerciseGroup?
                for entryDTO in groupDTO.exercises {
                    guard let exercise = exercisesByName[entryDTO.exercise.lowercased()] else {
                        // Validator lets bundle-external refs through only for
                        // library exercises; unresolved here means the ref
                        // points at neither — skip the entry.
                        continue
                    }
                    let containing: ExerciseGroup
                    if let group {
                        containing = group
                        target.addExercise(exercise, to: group, context: context)
                    } else {
                        containing = target.addExerciseInNewGroup(exercise, context: context)
                        containing.sets = groupDTO.sets
                        group = containing
                    }
                    if let entry = containing.sortedExercises.last {
                        entry.weight = entryDTO.weight
                        entry.reps = entryDTO.reps
                        entry.repsUpper = entryDTO.repsUpper
                        entry.durationSeconds = entryDTO.durationSeconds
                    }
                }
            }
        }

        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        var seenSessionKeys = Set(existingSessions.map { sessionKey($0.routineName, $0.startedAt) })
        for dto in bundle.sessions {
            let key = sessionKey(dto.routineName, dto.startedAt)
            guard !seenSessionKeys.contains(key) else {
                summary.sessionsSkipped += 1
                continue
            }
            seenSessionKeys.insert(key)

            let session = WorkoutSession(
                routineName: dto.routineName,
                startedAt: dto.startedAt,
                restSeconds: dto.restSeconds
            )
            session.endedAt = dto.endedAt
            context.insert(session)

            for setDTO in dto.sets {
                let log = SetLog(
                    order: setDTO.order,
                    groupIndex: setDTO.groupIndex,
                    setNumber: setDTO.setNumber,
                    exercise: exercisesByName[setDTO.exerciseName.lowercased()],
                    exerciseName: setDTO.exerciseName,
                    exerciseType: setDTO.exerciseType,
                    targetWeight: setDTO.targetWeight,
                    targetRepsLower: setDTO.targetRepsLower,
                    targetRepsUpper: setDTO.targetRepsUpper,
                    targetDuration: setDTO.targetDuration
                )
                log.actualWeight = setDTO.actualWeight
                log.actualReps = setDTO.actualReps
                log.actualDuration = setDTO.actualDuration
                log.completedAt = setDTO.completedAt
                log.session = session
                context.insert(log)
            }
            summary.sessionsAdded += 1
        }

        return summary
    }

    // MARK: - Helpers

    private static func sessionKey(_ name: String, _ startedAt: Date) -> String {
        "\(name.lowercased())|\(startedAt.timeIntervalSince1970)"
    }

    private static func dictionaryByLowercasedName<T>(_ items: [T], name: KeyPath<T, String>) -> [String: T] {
        var result: [String: T] = [:]
        for item in items {
            result[item[keyPath: name].lowercased()] = item
        }
        return result
    }

    private static func resolveEquipment(
        _ name: String,
        in cache: inout [String: Equipment],
        context: ModelContext
    ) -> Equipment {
        let key = name.lowercased()
        if let existing = cache[key] {
            return existing
        }
        let equipment = Equipment(name: name, isBuiltIn: false)
        context.insert(equipment)
        cache[key] = equipment
        return equipment
    }
}

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
        var equipmentConfigured = 0
        var librariesCreated = 0
        var librariesReplaced = 0
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
        let equipment = try context.fetch(FetchDescriptor<Equipment>())
        let libraries = try context.fetch(FetchDescriptor<EquipmentLibrary>())
        // Gear travels only when it says something: customs exist by
        // choice, built-ins only with user config — same convention as
        // exercises below. Unconfigured built-ins resolve from the seed
        // catalog on the importing side.
        let carryingGear = equipment.filter {
            !$0.isBuiltIn || $0.weightStep != nil || $0.metricsData != nil
        }
        return ExportBundle(
            units: units,
            // Export the user's LIBRARY: all customs, plus any built-in that's
            // in the library (the populate offer / manual adds — #328) or
            // that the user has annotated. Un-adopted catalog built-ins ship
            // with the app and resolve on import, so they stay out.
            exercises: exercises
                .filter { !$0.isBuiltIn || $0.inLibrary || $0.notes != nil || $0.videoURL != nil || $0.hasDefaultTargets || $0.metricsData != nil }
                .map(makeDTO),
            routines: routines.map(makeDTO),
            sessions: sessions.map(makeDTO),
            equipment: carryingGear.isEmpty ? nil : carryingGear.map(makeDTO),
            equipmentLibraries: libraries.isEmpty ? nil : libraries.sorted { $0.order < $1.order }.map(makeDTO)
        )
    }

    static func makeDTO(_ equipment: Equipment) -> EquipmentDTO {
        // Explicit per-store profile only (mirrors the exercise rule):
        // a built-in's seed-table suggestion resolves identically on the
        // importing side, so exporting it would just add noise.
        let explicitProfile = MetricProfile.decode(from: equipment.metricsData)
        return EquipmentDTO(
            name: equipment.name,
            isBuiltIn: equipment.isBuiltIn,
            weightStep: equipment.weightStep,
            metrics: explicitProfile.map { $0.metrics.map(\.rawValue) },
            distanceUnit: explicitProfile?.distanceUnit
        )
    }

    static func makeDTO(_ library: EquipmentLibrary) -> EquipmentLibraryDTO {
        EquipmentLibraryDTO(name: library.name, equipment: library.members.map(\.name))
    }

    static func makeDTO(_ exercise: Exercise) -> ExerciseDTO {
        // The profile travels only when it's an explicit per-store state
        // (metricsData set): built-ins' table profiles and legacy
        // customs' type-derived profiles resolve identically on the
        // importing side, and absent fields keep old bundles byte-stable.
        let explicitProfile = MetricProfile.decode(from: exercise.metricsData)
        return ExerciseDTO(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup,
            exerciseType: exercise.exerciseType,
            equipment: exercise.equipment.map(\.name),
            notes: exercise.notes,
            videoURL: exercise.videoURL,
            isBuiltIn: exercise.isBuiltIn,
            defaultWeight: exercise.defaultWeight,
            defaultReps: exercise.defaultReps,
            defaultRepsUpper: exercise.defaultRepsUpper,
            defaultDurationSeconds: exercise.defaultDurationSeconds,
            metrics: explicitProfile.map { $0.metrics.map(\.rawValue) },
            distanceUnit: explicitProfile?.distanceUnit,
            extraDefaults: MetricValues.toRaw(exercise.extraDefaults),
            // Carry library membership so it round-trips. Written only when
            // NOT in the library (the exception) — the common in-library case
            // stays absent, keeping files byte-clean.
            inLibrary: exercise.inLibrary ? nil : false
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
                            durationSeconds: entry.durationSeconds,
                            extraTargets: MetricValues.toRaw(entry.extraTargets)
                        )
                    },
                    restSeconds: group.restSecondsOverride
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
                    completedAt: log.completedAt,
                    extraTargets: MetricValues.toRaw(log.extraTargets),
                    extraActuals: MetricValues.toRaw(log.extraActuals),
                    restSecondsOverride: log.restSecondsOverride
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
        let preexistingEquipmentKeys = Set(equipmentByName.keys)

        // Gear config first, so exercise- and library-created references
        // resolve against configured records. The file is the source of
        // truth for a mentioned record's config (absent step/metrics
        // clear back to defaults); unmentioned gear is untouched.
        for dto in bundle.equipment ?? [] {
            let item = resolveEquipment(dto.name, in: &equipmentByName, context: context)
            item.weightStep = dto.weightStep
            if let metrics = dto.metrics, !metrics.isEmpty {
                item.suggestedProfile = MetricProfile(
                    metrics.compactMap(WorkoutMetric.init(rawValue:)),
                    distanceUnit: dto.distanceUnit ?? .meters
                )
            } else {
                item.metricsData = nil
            }
            summary.equipmentConfigured += 1
        }

        for dto in bundle.exercises {
            let key = dto.name.lowercased()
            if let existing = exercisesByName[key] {
                existing.muscleGroup = dto.muscleGroup
                existing.exerciseType = dto.exerciseType
                existing.notes = dto.notes
                existing.videoURL = dto.videoURL
                existing.equipment = dto.equipment.map { resolveEquipment($0, in: &equipmentByName, context: context) }
                existing.defaultWeight = dto.defaultWeight
                existing.defaultReps = dto.defaultReps
                existing.defaultRepsUpper = dto.defaultRepsUpper
                existing.defaultDurationSeconds = dto.defaultDurationSeconds
                // Wholesale like every field here: an absent profile
                // means "derive" (table/type), not "keep mine".
                existing.metricsData = profileData(from: dto)
                existing.extraDefaults = MetricValues.fromRaw(dto.extraDefaults)
                // Restore library membership (#328). Absent means in-library
                // (the common case + every pre-inLibrary file).
                existing.inLibrary = dto.inLibrary ?? true
                summary.exercisesUpdated += 1
            } else {
                let exercise = Exercise(
                    name: dto.name,
                    muscleGroup: dto.muscleGroup,
                    exerciseType: dto.exerciseType,
                    isBuiltIn: false,
                    notes: dto.notes,
                    videoURL: dto.videoURL
                )
                exercise.defaultWeight = dto.defaultWeight
                exercise.defaultReps = dto.defaultReps
                exercise.defaultRepsUpper = dto.defaultRepsUpper
                exercise.defaultDurationSeconds = dto.defaultDurationSeconds
                exercise.metricsData = profileData(from: dto)
                exercise.extraDefaults = MetricValues.fromRaw(dto.extraDefaults)
                exercise.inLibrary = dto.inLibrary ?? true
                context.insert(exercise)
                // Post-insert, like the seeder: pre-insert relationship
                // assignment loses nondeterministically.
                exercise.equipment = dto.equipment.map { resolveEquipment($0, in: &equipmentByName, context: context) }
                exercisesByName[key] = exercise
                summary.exercisesCreated += 1
            }
        }

        // Libraries replace-or-create by name; membership is exactly the
        // file's list (unknown names become custom gear via the same
        // resolver). Libraries the file doesn't mention are kept, and
        // the device's active-library pointer is never touched.
        let existingLibraries = try context.fetch(FetchDescriptor<EquipmentLibrary>())
        var librariesByName = dictionaryByLowercasedName(existingLibraries, name: \.name)
        var libraryOrder = (existingLibraries.map(\.order).max() ?? -1) + 1
        for dto in bundle.equipmentLibraries ?? [] {
            let members = dto.equipment.map { resolveEquipment($0, in: &equipmentByName, context: context) }
            if let existing = librariesByName[dto.name.lowercased()] {
                existing.equipment = members
                summary.librariesReplaced += 1
            } else {
                let library = EquipmentLibrary(name: dto.name, order: libraryOrder)
                libraryOrder += 1
                context.insert(library)
                // Post-insert, like every relationship here.
                library.equipment = members
                librariesByName[dto.name.lowercased()] = library
                summary.librariesCreated += 1
            }
        }

        // Pre-libraries bundles carry no membership statement, but gear
        // they create was effectively available under the old model —
        // join it to the active library so an old file imports with its
        // old meaning. Files WITH libraries are authoritative instead.
        if bundle.equipmentLibraries == nil {
            let created = Set(equipmentByName.keys).subtracting(preexistingEquipmentKeys)
            if !created.isEmpty, let active = EquipmentLibrary.active(context: context) {
                for key in created.sorted() {
                    if let item = equipmentByName[key] {
                        active.setMembership(item, true)
                    }
                }
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
                        containing.restSecondsOverride = groupDTO.restSeconds
                        group = containing
                    }
                    if let entry = containing.sortedExercises.last {
                        entry.weight = entryDTO.weight
                        entry.reps = entryDTO.reps
                        entry.repsUpper = entryDTO.repsUpper
                        entry.durationSeconds = entryDTO.durationSeconds
                        entry.extraTargets = MetricValues.fromRaw(entryDTO.extraTargets)
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
                let exercise = exercisesByName[setDTO.exerciseName.lowercased()]
                let log = SetLog(
                    order: setDTO.order,
                    groupIndex: setDTO.groupIndex,
                    setNumber: setDTO.setNumber,
                    exercise: exercise,
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
                log.extraTargets = MetricValues.fromRaw(setDTO.extraTargets)
                log.extraActuals = MetricValues.fromRaw(setDTO.extraActuals)
                log.restSecondsOverride = setDTO.restSecondsOverride
                log.metricsData = reconstructedProfileData(setDTO, exercise: exercise)
                log.session = session
                context.insert(log)
            }
            summary.sessionsAdded += 1
        }

        return summary
    }

    // MARK: - Helpers

    /// The stored profile a DTO's metrics imply — nil when absent, so
    /// the exercise derives (table for built-in names, legacy type
    /// otherwise) exactly like a never-exported one.
    private static func profileData(from dto: ExerciseDTO) -> Data? {
        guard let metrics = dto.metrics else { return nil }
        return MetricProfile(
            metrics.compactMap(WorkoutMetric.init(rawValue:)),
            distanceUnit: dto.distanceUnit ?? .meters
        ).encoded()
    }

    /// SetDTOs carry values, not profiles — the tracked set is implied
    /// by which fields are present. Classic-only sets stay nil (derive
    /// from the snapshotted exerciseType, byte-identical to old
    /// imports); sets with extras get a reconstructed snapshot so
    /// history renders every logged value. Distance denomination comes
    /// from the exercise when its reference resolves; meters otherwise —
    /// a display fallback, never a conversion.
    private static func reconstructedProfileData(_ setDTO: SessionDTO.SetDTO, exercise: Exercise?) -> Data? {
        let extras = Set(MetricValues.fromRaw(setDTO.extraTargets).keys)
            .union(MetricValues.fromRaw(setDTO.extraActuals).keys)
        guard !extras.isEmpty else { return nil }
        var metrics = Array(extras)
        if setDTO.targetWeight != nil || setDTO.actualWeight != nil { metrics.append(.weight) }
        if setDTO.targetRepsLower != nil || setDTO.actualReps != nil { metrics.append(.reps) }
        if setDTO.targetDuration != nil || setDTO.actualDuration != nil { metrics.append(.duration) }
        return MetricProfile(
            metrics,
            distanceUnit: exercise?.metricProfile.distanceUnit ?? .meters
        ).encoded()
    }

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

import Foundation
import SwiftData
import PlusPlusKit

/// Everything needed to revert one applied change. Depth 1 and
/// in-memory by design (the controller keeps only the latest): the
/// snapshots hold `PersistentIdentifier`s and interchange DTOs, which
/// are safe for the lifetime of one session but deliberately never
/// persisted — a stale inverse against a moved store is corruption bait.
struct InverseChange: Equatable {
    /// Creations revert by deleting what was made.
    var deleteCreated: [PersistentIdentifier] = []
    /// Field-level updates revert from before-images.
    var exerciseSnapshots: [ExerciseSnapshot] = []
    var entrySnapshots: [EntryTargetsSnapshot] = []
    var routineSettings: [RoutineSettingsSnapshot] = []
    var librarySnapshots: [LibrarySnapshot] = []
    /// Structural routine edits revert by rebuilding the routine's
    /// groups from a whole-structure DTO — in the SAME Routine model,
    /// so its `uuid` (presentation identity) survives the undo.
    var routineStructures: [RoutineStructureSnapshot] = []
    /// Deletions revert by recreating from interchange DTOs plus the
    /// device-local identity the DTO census-excludes (uuid, createdAt,
    /// the active pointer) so an undone delete restores the thing's
    /// identity, not just its content.
    var recreateExercises: [ExerciseDTO] = []
    var recreateRoutines: [RoutineSnapshot] = []
    var recreateLibraries: [LibrarySnapshot] = []

    var isEmpty: Bool {
        deleteCreated.isEmpty && exerciseSnapshots.isEmpty && entrySnapshots.isEmpty
            && routineSettings.isEmpty && librarySnapshots.isEmpty
            && routineStructures.isEmpty && recreateExercises.isEmpty
            && recreateRoutines.isEmpty && recreateLibraries.isEmpty
    }
}

/// Before-image of an exercise's Operator-editable fields.
struct ExerciseSnapshot: Equatable {
    let id: PersistentIdentifier
    let name: String
    let muscleGroup: MuscleGroup
    let exerciseType: ExerciseType
    let metricsData: Data?
    let notes: String?
    let inLibrary: Bool
    let defaultWeight: Double?
    let defaultReps: Int?
    let defaultRepsUpper: Int?
    let defaultDurationSeconds: Int?
    let extraDefaultsData: Data?
    let equipmentNames: [String]

    @MainActor
    init(exercise: Exercise) {
        id = exercise.persistentModelID
        name = exercise.name
        muscleGroup = exercise.muscleGroup
        exerciseType = exercise.exerciseType
        metricsData = exercise.metricsData
        notes = exercise.notes
        inLibrary = exercise.inLibrary
        defaultWeight = exercise.defaultWeight
        defaultReps = exercise.defaultReps
        defaultRepsUpper = exercise.defaultRepsUpper
        defaultDurationSeconds = exercise.defaultDurationSeconds
        extraDefaultsData = exercise.extraDefaultsData
        equipmentNames = exercise.equipment.map(\.name)
    }
}

/// Before-image of one routine entry's targets (the tracking-cascade
/// undo). Keyed by the entry's stable uuid.
struct EntryTargetsSnapshot: Equatable {
    let uuid: UUID?
    let weight: Double?
    let reps: Int?
    let repsUpper: Int?
    let durationSeconds: Int?
    let extraTargetsData: Data?

    @MainActor
    init(entry: RoutineExercise) {
        uuid = entry.uuid
        weight = entry.weight
        reps = entry.reps
        repsUpper = entry.repsUpper
        durationSeconds = entry.durationSeconds
        extraTargetsData = entry.extraTargetsData
    }
}

/// Before-image of a routine's settings (non-structural updates).
struct RoutineSettingsSnapshot: Equatable {
    let uuid: UUID?
    let name: String
    let restSeconds: Int
    let notes: String?
    let scheduleData: Data?

    @MainActor
    init(routine: Routine) {
        uuid = routine.uuid
        name = routine.name
        restSeconds = routine.restSeconds
        notes = routine.notes
        scheduleData = routine.scheduleData
    }
}

/// Whole-structure before-image: settings + the group/entry tree as an
/// interchange DTO, restored into the same Routine model.
struct RoutineStructureSnapshot: Equatable {
    let uuid: UUID?
    let dto: RoutineDTO

    @MainActor
    init(routine: Routine) {
        uuid = routine.uuid
        dto = InterchangeMapping.makeDTO(routine)
    }
}

/// The recreate payload for a deleted routine: the interchange DTO plus
/// the device-local identity it census-excludes. `createdAt` is the
/// due-ness anchor (#354: days before a routine joined never count as
/// carried), and `uuid` is presentation identity — losing either would
/// make an undone delete come back subtly different.
struct RoutineSnapshot: Equatable {
    let dto: RoutineDTO
    let uuid: UUID?
    let createdAt: Date

    @MainActor
    init(routine: Routine) {
        dto = InterchangeMapping.makeDTO(routine)
        uuid = routine.uuid
        createdAt = routine.createdAt
    }
}

/// Before-image of a library (also the recreate payload for a deleted
/// one — name + membership + active-ness is a library's whole state).
struct LibrarySnapshot: Equatable {
    let uuid: UUID
    let name: String
    let memberNames: [String]
    /// Whether this was the ACTIVE library when snapshotted — a deleted
    /// active library re-points the device pointer, so its undo points
    /// it back.
    let isActive: Bool

    @MainActor
    init(library: EquipmentLibrary, isActive: Bool = false) {
        uuid = library.uuid
        name = library.name
        memberNames = library.members.map(\.name)
        self.isActive = isActive
    }
}

// MARK: - Undo execution

extension ChangeEngine {
    /// Applies an inverse, returning the names of items whose recreate
    /// was SKIPPED because a same-name item now exists (created after
    /// the delete, before the undo) — the caller must report those, not
    /// claim a clean "Undone." Ordering matters: recreated exercises
    /// must exist before routine structures resolve entry names against
    /// them.
    @MainActor
    func performUndo(_ inverse: InverseChange) throws -> [String] {
        var skipped: [String] = []
        for dto in inverse.recreateExercises {
            if try !recreateExercise(from: dto, in: context) { skipped.append(dto.name) }
        }
        for snapshot in inverse.recreateLibraries {
            if try !recreateLibrary(from: snapshot, in: context) { skipped.append(snapshot.name) }
        }
        for snapshot in inverse.recreateRoutines {
            if try !recreateRoutine(from: snapshot, in: context) { skipped.append(snapshot.dto.name) }
        }
        for snapshot in inverse.routineStructures {
            try restoreStructure(snapshot, in: context)
        }
        // The bulk cases (a tracking conversion snapshots every matched
        // exercise + every cascaded entry) hoist their table fetches out
        // of the per-snapshot loop.
        if !inverse.exerciseSnapshots.isEmpty {
            let allGear = try context.fetch(FetchDescriptor<Equipment>())
            let gearByName = Dictionary(grouping: allGear) { $0.name }
            for snapshot in inverse.exerciseSnapshots {
                restoreExercise(snapshot, gearByName: gearByName)
            }
        }
        if !inverse.entrySnapshots.isEmpty {
            let allEntries = try context.fetch(FetchDescriptor<RoutineExercise>())
            let entriesByUUID = Dictionary(
                allEntries.compactMap { entry in entry.uuid.map { ($0, entry) } },
                uniquingKeysWith: { first, _ in first }
            )
            for snapshot in inverse.entrySnapshots {
                restoreEntry(snapshot, entriesByUUID: entriesByUUID)
            }
        }
        for snapshot in inverse.routineSettings {
            try restoreRoutineSettings(snapshot, in: context)
        }
        for snapshot in inverse.librarySnapshots {
            try restoreLibrary(snapshot, in: context)
        }
        for id in inverse.deleteCreated {
            if let model = context.model(for: id) as? Routine {
                context.delete(model)
            } else if let model = context.model(for: id) as? Exercise {
                context.delete(model)
            } else if let model = context.model(for: id) as? EquipmentLibrary {
                context.delete(model)
            }
        }
        return skipped
    }

    // MARK: - Recreates (delete undo)

    /// Returns false when a same-name exercise now exists and the
    /// recreate was skipped.
    @MainActor
    private func recreateExercise(from dto: ExerciseDTO, in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        guard !existing.contains(where: { $0.name.compare(dto.name, options: .caseInsensitive) == .orderedSame }) else { return false }
        let exercise = Exercise(
            name: dto.name,
            muscleGroup: dto.muscleGroup,
            exerciseType: dto.exerciseType,
            isBuiltIn: dto.isBuiltIn,
            notes: dto.notes,
            videoURL: dto.videoURL
        )
        context.insert(exercise)
        let allGear = try context.fetch(FetchDescriptor<Equipment>())
        exercise.equipment = dto.equipment.compactMap { name in
            allGear.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
        }
        exercise.defaultWeight = dto.defaultWeight
        exercise.defaultReps = dto.defaultReps
        exercise.defaultRepsUpper = dto.defaultRepsUpper
        exercise.defaultDurationSeconds = dto.defaultDurationSeconds
        if let metrics = dto.metrics {
            exercise.metricProfile = MetricProfile(
                metrics.compactMap(WorkoutMetric.init(rawValue:)),
                distanceUnit: dto.distanceUnit ?? .meters
            )
        }
        exercise.extraDefaults = MetricValues.fromRaw(dto.extraDefaults)
        exercise.inLibrary = dto.inLibrary ?? true
        exercise.defaultHeartRateTargetData = InterchangeMapping.encodeHeartRate(dto.defaultHeartRateTarget)
        return true
    }

    /// Returns false when a same-name library now exists.
    @MainActor
    private func recreateLibrary(from snapshot: LibrarySnapshot, in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<EquipmentLibrary>())
        guard !existing.contains(where: { $0.name.compare(snapshot.name, options: .caseInsensitive) == .orderedSame }) else { return false }
        // max()+1, not count: library deletes leave order gaps by design.
        let library = EquipmentLibrary(name: snapshot.name, order: (existing.map(\.order).max() ?? -1) + 1)
        context.insert(library)
        // Restore the ORIGINAL uuid: the active-library pointer stores
        // it, so a fresh uuid would silently strand an undone-deleted
        // active library on the order-first fallback.
        library.uuid = snapshot.uuid
        try setMembers(of: library, to: snapshot.memberNames, in: context)
        // The delete re-pointed the device pointer to a survivor; the
        // undo points it back at the restored active library.
        if snapshot.isActive {
            UserDefaults.standard.set(snapshot.uuid.uuidString, forKey: EquipmentLibrary.activeIDKey)
        }
        return true
    }

    /// Returns false when a same-name routine now exists.
    @MainActor
    private func recreateRoutine(from snapshot: RoutineSnapshot, in context: ModelContext) throws -> Bool {
        let dto = snapshot.dto
        let existing = try context.fetch(FetchDescriptor<Routine>())
        guard !existing.contains(where: { $0.name.compare(dto.name, options: .caseInsensitive) == .orderedSame }) else { return false }
        let routine = Routine(name: dto.name, order: existing.count, restSeconds: dto.restSeconds, notes: dto.notes)
        context.insert(routine)
        // Restore device-local identity the DTO excludes: uuid keeps
        // presentation/nav resolving, createdAt keeps the due-ness
        // anchor (#354) — without it a restored Mon/Thu routine forgets
        // the Monday it just carried over.
        if let uuid = snapshot.uuid { routine.uuid = uuid }
        routine.createdAt = snapshot.createdAt
        routine.schedule = dto.schedule ?? .unscheduled
        try rebuildGroups(of: routine, from: dto, in: context)
        return true
    }

    // MARK: - Restores (update undo)

    @MainActor
    private func restoreStructure(_ snapshot: RoutineStructureSnapshot, in context: ModelContext) throws {
        guard let uuid = snapshot.uuid, let routine = context.routine(uuid: uuid) else { return }
        for group in routine.groups {
            context.delete(group)
        }
        routine.name = snapshot.dto.name
        routine.restSeconds = snapshot.dto.restSeconds
        routine.notes = snapshot.dto.notes
        routine.schedule = snapshot.dto.schedule ?? .unscheduled
        try rebuildGroups(of: routine, from: snapshot.dto, in: context)
    }

    /// The interchange import's rebuild pattern: groups and entries are
    /// reassembled through the routine's own structure mutations so
    /// order invariants hold; entry names that no longer resolve are
    /// skipped (mirrors import).
    @MainActor
    private func rebuildGroups(of routine: Routine, from dto: RoutineDTO, in context: ModelContext) throws {
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        let byName = Dictionary(grouping: allExercises) { $0.name.lowercased() }
        for groupDTO in dto.groups {
            var group: ExerciseGroup?
            for entryDTO in groupDTO.exercises {
                guard let exercise = byName[entryDTO.exercise.lowercased()]?.first else { continue }
                let entry: RoutineExercise
                if let group {
                    entry = routine.addExercise(exercise, to: group, context: context)
                } else {
                    let containing = routine.addExerciseInNewGroup(exercise, context: context)
                    containing.sets = groupDTO.sets
                    containing.restSecondsOverride = groupDTO.restSeconds
                    group = containing
                    guard let first = containing.sortedExercises.last else { continue }
                    entry = first
                }
                entry.weight = entryDTO.weight
                entry.reps = entryDTO.reps
                entry.repsUpper = entryDTO.repsUpper
                entry.durationSeconds = entryDTO.durationSeconds
                entry.extraTargets = MetricValues.fromRaw(entryDTO.extraTargets)
                entry.heartRateTarget = entryDTO.heartRateTarget
            }
        }
    }

    @MainActor
    private func restoreExercise(_ snapshot: ExerciseSnapshot, gearByName: [String: [Equipment]]) {
        guard let exercise = context.model(for: snapshot.id) as? Exercise, !exercise.isDeleted else { return }
        exercise.name = snapshot.name
        exercise.muscleGroup = snapshot.muscleGroup
        exercise.exerciseType = snapshot.exerciseType
        exercise.metricsData = snapshot.metricsData
        exercise.notes = snapshot.notes
        exercise.inLibrary = snapshot.inLibrary
        exercise.defaultWeight = snapshot.defaultWeight
        exercise.defaultReps = snapshot.defaultReps
        exercise.defaultRepsUpper = snapshot.defaultRepsUpper
        exercise.defaultDurationSeconds = snapshot.defaultDurationSeconds
        exercise.extraDefaultsData = snapshot.extraDefaultsData
        exercise.equipment = snapshot.equipmentNames.compactMap { gearByName[$0]?.first }
    }

    @MainActor
    private func restoreEntry(_ snapshot: EntryTargetsSnapshot, entriesByUUID: [UUID: RoutineExercise]) {
        guard let uuid = snapshot.uuid,
              let entry = entriesByUUID[uuid], !entry.isDeleted else { return }
        entry.weight = snapshot.weight
        entry.reps = snapshot.reps
        entry.repsUpper = snapshot.repsUpper
        entry.durationSeconds = snapshot.durationSeconds
        entry.extraTargetsData = snapshot.extraTargetsData
    }

    @MainActor
    private func restoreRoutineSettings(_ snapshot: RoutineSettingsSnapshot, in context: ModelContext) throws {
        guard let uuid = snapshot.uuid, let routine = context.routine(uuid: uuid) else { return }
        routine.name = snapshot.name
        routine.restSeconds = snapshot.restSeconds
        routine.notes = snapshot.notes
        routine.scheduleData = snapshot.scheduleData
    }

    @MainActor
    private func restoreLibrary(_ snapshot: LibrarySnapshot, in context: ModelContext) throws {
        let libraries = try context.fetch(FetchDescriptor<EquipmentLibrary>())
        guard let library = libraries.first(where: { $0.uuid == snapshot.uuid && !$0.isDeleted }) else { return }
        library.name = snapshot.name
        try setMembers(of: library, to: snapshot.memberNames, in: context)
    }

    @MainActor
    private func setMembers(of library: EquipmentLibrary, to names: [String], in context: ModelContext) throws {
        let allGear = try context.fetch(FetchDescriptor<Equipment>())
        for member in library.members {
            library.setMembership(member, false)
        }
        for name in names {
            if let item = allGear.first(where: { $0.name == name }) {
                library.setMembership(item, true)
            }
        }
    }
}

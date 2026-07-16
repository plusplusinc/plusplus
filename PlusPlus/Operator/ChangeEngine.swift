import Foundation
import SwiftData
import PlusPlusKit

/// The deterministic half of Operator's "the model proposes, the app
/// disposes" contract. The on-device model only ever produces a
/// `ChangeSpec`; this engine validates it, resolves it against live
/// data, tiers it (small edits apply now with an undo, bulk/destructive
/// edits stage a preview and touch NOTHING until Apply), applies it
/// under the SwiftData laws, and can invert what it applied. No model
/// output is ever executed directly.
///
/// Previews carry the SPEC, not live references — Apply re-resolves at
/// tap time, so data that moved between staging and tapping is re-read,
/// never stale-pointer-mutated.
@MainActor
final class ChangeEngine {
    /// Internal so the undo executor (ChangeInverse.swift) shares it.
    let context: ModelContext
    /// Post-apply hook seam (widget snapshot, watch plan, calendar
    /// reconcile). Injected so unit tests observe invocations without
    /// the live singletons; the chat surface wires the real ones.
    var afterApply: (ModelContext) -> Void

    init(context: ModelContext, afterApply: @escaping (ModelContext) -> Void = { _ in }) {
        self.context = context
        self.afterApply = afterApply
    }

    // MARK: - Outcomes

    struct ChangePreview: Equatable {
        let id: UUID
        /// Re-resolved at Apply time.
        let spec: ChangeSpec
        let headline: String
        let lines: [String]
        let affectedCount: Int
    }

    struct ChangeReceipt: Equatable {
        let id: UUID
        /// "Renamed Push to Push Day."
        let summary: String
        let destinations: [OperatorDestination]
    }

    struct AppliedChange: Equatable {
        let receipt: ChangeReceipt
        let inverse: InverseChange
    }

    enum ChangeOutcome: Equatable {
        case applied(AppliedChange)
        case staged(ChangePreview)
        case invalid(String)

        /// The terse result string the propose_change tool hands back to
        /// the model — it steers narration, never carries the details
        /// (the cards do). An undo's own result has an EMPTY inverse, so
        /// it must not advertise an undo affordance that doesn't exist
        /// (depth 1: no undo-of-undo).
        var digest: String {
            switch self {
            case .applied(let change) where change.inverse.isEmpty:
                "APPLIED: \(change.receipt.summary)"
            case .applied(let change):
                "APPLIED: \(change.receipt.summary) A receipt with undo is shown. Do not restate the details."
            case .staged(let preview):
                "STAGED: \(([preview.headline] + preview.lines).joined(separator: " · ")). A preview card with apply and cancel is shown. Tell the user to review it; do not claim it happened."
            case .invalid(let reason):
                "INVALID: \(reason)"
            }
        }
    }

    // MARK: - Entry points

    /// Validate → resolve → tier → stage or apply.
    func propose(_ rawSpec: ChangeSpec) -> ChangeOutcome {
        let spec = rawSpec.normalized
        let issues = spec.validationIssues()
        guard issues.isEmpty else {
            return .invalid(issues.joined(separator: "; "))
        }
        switch resolveGuarded(spec) {
        case .failure(let reason):
            return .invalid(reason)
        case .success(let resolution):
            if resolution.tier == .previewRequired {
                let summary = resolution.previewSummary()
                return .staged(ChangePreview(
                    id: UUID(),
                    spec: spec,
                    headline: summary.headline,
                    lines: summary.lines,
                    affectedCount: resolution.affectedCount
                ))
            }
            return applyGuarded(resolution)
        }
    }

    /// The preview card's Apply tap: re-resolve the stored spec and
    /// apply regardless of tier (the user just confirmed it).
    func applyStaged(_ spec: ChangeSpec) -> ChangeOutcome {
        switch resolveGuarded(spec.normalized) {
        case .failure(let reason):
            return .invalid(reason)
        case .success(let resolution):
            return applyGuarded(resolution)
        }
    }

    /// Revert an applied change. Depth 1, in-memory — the controller
    /// keeps only the latest inverse. An honest partial: recreates
    /// skipped because a same-name item now exists are NAMED, never
    /// papered over with a clean "Undone."
    func undo(_ inverse: InverseChange) -> ChangeOutcome {
        do {
            let skipped = try performUndo(inverse)
            try context.save()
            afterApply(context)
            let summary = skipped.isEmpty
                ? "Undone."
                : "Undone, except \(skipped.joined(separator: ", ")): a same-name item exists now, so it was left alone."
            return .applied(AppliedChange(
                receipt: ChangeReceipt(id: UUID(), summary: summary, destinations: []),
                inverse: InverseChange()
            ))
        } catch {
            context.rollback()
            return .invalid("could not undo: \(error.localizedDescription)")
        }
    }

    private func resolveGuarded(_ spec: ChangeSpec) -> Selection<Resolution> {
        do {
            return try resolve(spec)
        } catch {
            return .failure("could not read data: \(error.localizedDescription)")
        }
    }

    /// Any mid-apply error rolls the context back — an apply is all or
    /// nothing, never a half-mutated store.
    private func applyGuarded(_ resolution: Resolution) -> ChangeOutcome {
        do {
            return try .applied(apply(resolution))
        } catch {
            context.rollback()
            return .invalid(error.localizedDescription)
        }
    }

    private enum Selection<T> {
        case success(T)
        case failure(String)
    }

    private enum EngineError: LocalizedError {
        case reason(String)
        var errorDescription: String? {
            if case .reason(let text) = self { return text }
            return nil
        }
    }

    /// #187's global floor prescriptions (10 reps / 45 s) — the same
    /// values `Routine.applyDefaultTargets` falls back to. One home, so
    /// the preview's promise and the apply's write can never diverge.
    enum FallbackTarget {
        static let reps = 10
        static let durationSeconds = 45
    }

    // MARK: - Resolution

    /// Everything an apply needs, computed up front so tiering and
    /// previews describe exactly what apply would touch.
    private struct Resolution {
        let spec: ChangeSpec
        var routines: [Routine] = []
        var exercises: [Exercise] = []
        var libraries: [EquipmentLibrary] = []
        /// Superset ops: the routine and the member entries involved.
        var supersetRoutine: Routine?
        var supersetMembers: [RoutineExercise] = []
        var supersetGroups: [ExerciseGroup] = []
        /// Exercise ops: live routine entries dragged along by a
        /// tracking conversion or a custom-exercise delete.
        var cascadeEntries: [RoutineExercise] = []
        /// Resolved gear for values.equipment.
        var equipment: [Equipment] = []
        /// Resolved exercises for routine addExercises.
        var exercisesToAdd: [Exercise] = []

        var values: ChangeValues { spec.values ?? ChangeValues() }

        /// A create always affects exactly the one thing it makes.
        var affectedCount: Int {
            if spec.operation == .create { return 1 }
            switch spec.entity {
            case .routine: return routines.count
            case .exercise: return exercises.count
            case .superset: return max(supersetMembers.count, supersetGroups.count)
            case .library: return libraries.count
            }
        }

        var tier: ChangeTier {
            ChangeTierPolicy.tier(
                operation: spec.operation,
                entity: spec.entity,
                affectedCount: affectedCount,
                changesTracking: values.trackBy != nil,
                cascadesToEntries: !cascadeEntries.isEmpty
            )
        }

        func previewSummary() -> ChangePreviewSummary {
            var changes: [String] = []
            if let mode = values.trackBy {
                var line = "track by \(mode.spokenName)"
                if let current = spec.filter?.trackedBy {
                    line += " · was \(current.spokenName)"
                }
                changes.append(line)
                // Only promise a per-set duration when one was actually
                // requested; otherwise each exercise keeps (or falls back
                // from) its own default and no single number is true.
                if mode == .duration, let seconds = values.durationSeconds {
                    changes.append("\(seconds) s per set")
                }
                if !cascadeEntries.isEmpty {
                    changes.append("updates \(cascadeEntries.count) routine \(cascadeEntries.count == 1 ? "entry" : "entries")")
                }
            }
            if let days = values.scheduleDays {
                changes.append(days.isEmpty ? "schedule cleared" : "scheduled \(RoutineSchedule.weekdays(days).shortLabel)")
            }
            if let name = values.name { changes.append("renamed to \(name)") }
            if let rest = values.restSeconds { changes.append("rest \(rest) s") }
            if let sets = values.sets { changes.append("\(sets) sets") }
            if spec.operation == .delete, spec.entity == .exercise {
                let builtIns = exercises.filter(\.isBuiltIn).count
                let customs = exercises.count - builtIns
                if builtIns > 0 { changes.append("\(builtIns) built-in\(builtIns == 1 ? " leaves" : "s leave") the library, not the catalog") }
                if customs > 0 { changes.append("\(customs) custom\(customs == 1 ? "" : "s") deleted, entries removed from routines") }
            }
            let names: [String]
            switch spec.entity {
            case .routine: names = routines.map(\.name)
            case .exercise: names = exercises.map(\.name)
            case .superset: names = supersetMembers.compactMap { $0.exercise?.name }
            case .library: names = libraries.map(\.name)
            }
            return ChangePreviewSummary.make(
                operation: spec.operation,
                entity: spec.entity,
                count: affectedCount,
                sampleNames: names,
                changeDescriptions: changes
            )
        }
    }

    private func resolve(_ spec: ChangeSpec) throws -> Selection<Resolution> {
        var resolution = Resolution(spec: spec)
        let values = spec.values ?? ChangeValues()

        // values.equipment resolves against existing gear for exercises
        // and libraries alike — Operator references gear, it doesn't
        // invent it.
        if let gearNames = values.equipment {
            let allGear = try context.fetch(FetchDescriptor<Equipment>())
            var resolvedGear: [Equipment] = []
            for name in gearNames {
                switch match(name: name, in: allGear, by: \.name) {
                case .one(let item): resolvedGear.append(item)
                case .many:
                    return .failure("equipment \(name) is ambiguous")
                case .none:
                    return .failure("no equipment named \(name)\(closestText(name, in: allGear.map(\.name)))")
                }
            }
            resolution.equipment = resolvedGear
        }

        switch spec.entity {
        case .routine:
            let all = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))
            if spec.operation == .create {
                if let missing = try resolveExercisesToAdd(values.addExercises, into: &resolution) {
                    return .failure(missing)
                }
                return .success(resolution)
            }
            switch selectNamed(spec: spec, from: all, by: \.name, matchesFilter: { routine, filter in
                guard let fragment = filter.normalizedNameContains else { return !filter.isEmpty }
                return routine.name.localizedCaseInsensitiveContains(fragment)
            }) {
            case .failure(let reason): return .failure(reason)
            case .success(let matched): resolution.routines = matched
            }
            if resolution.routines.isEmpty { return .failure("no matching routines") }
            if spec.operation == .update, let newName = ChangeFilter.normalized(values.name) {
                guard resolution.routines.count == 1, let target = resolution.routines.first else {
                    return .failure("renaming needs exactly one target routine")
                }
                if all.contains(where: { $0 !== target && $0.name.compare(newName, options: .caseInsensitive) == .orderedSame }) {
                    return .failure("a routine named \(newName) already exists")
                }
            }
            if let missing = try resolveExercisesToAdd(values.addExercises, into: &resolution) {
                return .failure(missing)
            }

        case .exercise:
            let all = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))
            if spec.operation == .create {
                let name = ChangeFilter.normalized(values.name) ?? ""
                if all.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                    return .failure("an exercise named \(name) already exists")
                }
                return .success(resolution)
            }
            switch selectNamed(spec: spec, from: all, by: \.name, matchesFilter: { exercise, filter in
                if let fragment = filter.normalizedNameContains,
                   !exercise.name.localizedCaseInsensitiveContains(fragment) { return false }
                if let muscle = filter.muscleGroup, exercise.muscleGroup != muscle { return false }
                if let mode = filter.trackedBy, !mode.matches(exercise.metricProfile) { return false }
                return !filter.isEmpty
            }) {
            case .failure(let reason): return .failure(reason)
            case .success(let matched): resolution.exercises = matched
            }
            if resolution.exercises.isEmpty { return .failure("no matching exercises") }
            if spec.operation == .update, let newName = ChangeFilter.normalized(values.name) {
                guard resolution.exercises.count == 1, let target = resolution.exercises.first else {
                    return .failure("renaming needs exactly one target exercise")
                }
                if target.isBuiltIn {
                    return .failure("built-in exercises keep their names")
                }
                if all.contains(where: { $0 !== target && $0.name.compare(newName, options: .caseInsensitive) == .orderedSame }) {
                    return .failure("an exercise named \(newName) already exists")
                }
            }
            // A tracking conversion (or a custom delete) drags every live
            // routine entry of the touched exercises along with it.
            if values.trackBy != nil || spec.operation == .delete {
                let allEntries = try context.fetch(FetchDescriptor<RoutineExercise>())
                let affected = Set(resolution.exercises.map(\.persistentModelID))
                resolution.cascadeEntries = allEntries.filter { entry in
                    guard !entry.isDeleted, let exercise = entry.exercise else { return false }
                    return affected.contains(exercise.persistentModelID)
                }
            }

        case .superset:
            guard let routineName = spec.filter?.normalizedInRoutine else {
                return .failure("superset changes need filter.inRoutine")
            }
            let all = try context.fetch(FetchDescriptor<Routine>())
            let routine: Routine
            switch match(name: routineName, in: all, by: \.name) {
            case .one(let matched): routine = matched
            case .many(let candidates):
                return .failure("\(routineName) matches \(candidates.prefix(4).map(\.name).joined(separator: ", ")). Ask the user which.")
            case .none:
                return .failure("no routine named \(routineName)\(closestText(routineName, in: all.map(\.name)))")
            }
            resolution.supersetRoutine = routine
            if spec.operation == .delete, spec.targets.isEmpty {
                resolution.supersetGroups = routine.sortedGroups.filter(\.isSuperset)
                if resolution.supersetGroups.isEmpty {
                    return .failure("\(routine.name) has no supersets")
                }
            } else {
                var members: [RoutineExercise] = []
                for target in spec.targets {
                    switch matchEntry(named: target, in: routine) {
                    case .one(let member):
                        members.append(member)
                    case .many(let candidates):
                        return .failure("\(target) matches \(candidates.prefix(4).joined(separator: ", ")) in \(routine.name). Ask the user which.")
                    case .none:
                        return .failure("no \(target) in \(routine.name)")
                    }
                }
                resolution.supersetMembers = orderedUnique(members)
                resolution.supersetGroups = orderedUnique(members.compactMap(\.group))
                if spec.operation == .update, resolution.supersetMembers.count < 2, values.sets == nil {
                    return .failure("a superset needs at least two exercises")
                }
            }

        case .library:
            let all = try context.fetch(FetchDescriptor<EquipmentLibrary>(sortBy: [SortDescriptor(\.order)]))
            if spec.operation == .create {
                let name = ChangeFilter.normalized(values.name) ?? ""
                if all.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                    return .failure("a library named \(name) already exists")
                }
                return .success(resolution)
            }
            switch selectNamed(spec: spec, from: all, by: \.name, matchesFilter: { library, filter in
                guard let fragment = filter.normalizedNameContains else { return !filter.isEmpty }
                return library.name.localizedCaseInsensitiveContains(fragment)
            }) {
            case .failure(let reason): return .failure(reason)
            case .success(let matched): resolution.libraries = matched
            }
            if resolution.libraries.isEmpty { return .failure("no matching libraries") }
            if spec.operation == .delete, resolution.libraries.count >= all.count {
                return .failure("keep at least one library")
            }
            if spec.operation == .update, let newName = ChangeFilter.normalized(values.name) {
                guard resolution.libraries.count == 1, let target = resolution.libraries.first else {
                    return .failure("renaming needs exactly one target library")
                }
                if all.contains(where: { $0 !== target && $0.name.compare(newName, options: .caseInsensitive) == .orderedSame }) {
                    return .failure("a library named \(newName) already exists")
                }
            }
        }
        return .success(resolution)
    }

    /// Routine addExercises resolution; returns an invalid reason or nil.
    private func resolveExercisesToAdd(_ names: [String]?, into resolution: inout Resolution) throws -> String? {
        guard let names, !names.isEmpty else { return nil }
        let all = try context.fetch(FetchDescriptor<Exercise>())
        var resolved: [Exercise] = []
        for name in names {
            switch match(name: name, in: all, by: \.name) {
            case .one(let exercise): resolved.append(exercise)
            case .many(let candidates):
                return "\(name) matches \(candidates.prefix(4).map(\.name).joined(separator: ", ")). Ask the user which."
            case .none:
                return "no exercise named \(name)\(closestText(name, in: all.map(\.name)))"
            }
        }
        resolution.exercisesToAdd = resolved
        return nil
    }

    // MARK: - Apply

    private func apply(_ resolution: Resolution) throws -> AppliedChange {
        let spec = resolution.spec
        let values = resolution.values
        var inverse = InverseChange()
        let summary: String
        var destinations: [OperatorDestination] = []
        /// Creations invert by deletion, but the IDs are captured only
        /// AFTER the save below — a pre-save `persistentModelID` is the
        /// temporary one and dies at the temp→permanent swap (the
        /// swiftdata.md law), which would leave undo resolving nothing.
        var created: [any PersistentModel] = []

        switch (spec.operation, spec.entity) {
        case (.create, .routine):
            let existing = try context.fetch(FetchDescriptor<Routine>())
            let name = Routine.uniqueName(ChangeFilter.normalized(values.name) ?? "Routine", among: existing)
            let routine = Routine(name: name, order: existing.count, restSeconds: values.restSeconds ?? 90, notes: values.notes)
            context.insert(routine)
            if let days = values.scheduleDays {
                routine.schedule = days.isEmpty ? RoutineSchedule.unscheduled : .weekdays(days)
            }
            for exercise in resolution.exercisesToAdd {
                routine.addExerciseInNewGroup(exercise, context: context)
            }
            created = [routine]
            summary = resolution.exercisesToAdd.isEmpty
                ? "Created \(name)."
                : "Created \(name) · \(resolution.exercisesToAdd.count) exercise\(resolution.exercisesToAdd.count == 1 ? "" : "s")."
            destinations = routine.uuid.map { [OperatorDestination.routine($0)] } ?? []

        case (.create, .exercise):
            let name = ChangeFilter.normalized(values.name) ?? "Exercise"
            let exercise = Exercise(name: name, muscleGroup: values.muscleGroup ?? .fullBody)
            context.insert(exercise)
            exercise.equipment = resolution.equipment
            if let mode = values.trackBy { exercise.metricProfile = mode.profile }
            exercise.notes = values.notes
            exercise.defaultReps = values.reps
            exercise.defaultDurationSeconds = values.durationSeconds
            exercise.defaultWeight = values.weight
            created = [exercise]
            summary = "Created \(name)."
            destinations = [.exercisesTab]

        case (.create, .library):
            let existing = try context.fetch(FetchDescriptor<EquipmentLibrary>())
            let name = ChangeFilter.normalized(values.name) ?? "Library"
            // max()+1, not count: library deletes deliberately leave order
            // gaps (the tray's documented invariant), so count can collide.
            let library = EquipmentLibrary(name: name, order: (existing.map(\.order).max() ?? -1) + 1)
            context.insert(library)
            for item in resolution.equipment { library.setMembership(item, true) }
            created = [library]
            summary = "Created \(name)\(resolution.equipment.isEmpty ? "" : " · \(resolution.equipment.count) item\(resolution.equipment.count == 1 ? "" : "s")")."
            destinations = [.equipmentTab]

        case (.update, .routine):
            // Pre-mutation names, so a rename receipt can say what the
            // thing WAS called.
            let subjectNames = resolution.routines.map(\.name)
            let structural = values.addExercises != nil || values.removeExercises != nil
            for routine in resolution.routines {
                if structural {
                    inverse.routineStructures.append(RoutineStructureSnapshot(routine: routine))
                } else {
                    inverse.routineSettings.append(RoutineSettingsSnapshot(routine: routine))
                }
            }
            for routine in resolution.routines {
                if let newName = ChangeFilter.normalized(values.name) {
                    routine.name = newName
                }
                if let rest = values.restSeconds { routine.restSeconds = rest }
                if let notes = values.notes { routine.notes = notes }
                if let days = values.scheduleDays {
                    routine.schedule = days.isEmpty ? RoutineSchedule.unscheduled : .weekdays(days)
                }
                for exercise in resolution.exercisesToAdd {
                    routine.addExerciseInNewGroup(exercise, context: context)
                }
                if let removals = values.removeExercises {
                    try removeEntries(named: removals, from: routine)
                }
            }
            summary = updateSummary(names: subjectNames, values: values)
            if resolution.routines.count == 1, let uuid = resolution.routines[0].uuid {
                destinations = [.routine(uuid)]
            }

        case (.update, .exercise):
            let subjectNames = resolution.exercises.map(\.name)
            for exercise in resolution.exercises {
                inverse.exerciseSnapshots.append(ExerciseSnapshot(exercise: exercise))
            }
            for entry in resolution.cascadeEntries {
                inverse.entrySnapshots.append(EntryTargetsSnapshot(entry: entry))
            }
            for exercise in resolution.exercises {
                if let newName = ChangeFilter.normalized(values.name) { exercise.name = newName }
                if let muscle = values.muscleGroup { exercise.muscleGroup = muscle }
                if let notes = values.notes { exercise.notes = notes }
                if values.equipment != nil { exercise.equipment = resolution.equipment }
                if let reps = values.reps { exercise.defaultReps = reps }
                if let duration = values.durationSeconds { exercise.defaultDurationSeconds = duration }
                if let weight = values.weight { exercise.defaultWeight = weight }
                if let mode = values.trackBy {
                    convertTracking(of: exercise, to: mode, requestedDuration: values.durationSeconds, requestedReps: values.reps)
                }
            }
            if values.trackBy != nil {
                for entry in resolution.cascadeEntries {
                    guard let exercise = entry.exercise else { continue }
                    convertEntryTargets(entry, profile: exercise.metricProfile, exercise: exercise)
                }
            }
            summary = updateSummary(names: subjectNames, values: values)
            destinations = [.exercisesTab]

        case (.update, .superset), (.delete, .superset):
            guard let routine = resolution.supersetRoutine else {
                throw EngineError.reason("superset routine went missing")
            }
            inverse.routineStructures.append(RoutineStructureSnapshot(routine: routine))
            if spec.operation == .delete {
                let dissolving = resolution.supersetGroups.filter(\.isSuperset)
                for group in dissolving {
                    dissolve(group, in: routine)
                }
                summary = "Dissolved \(dissolving.count == 1 ? "the superset" : "\(dissolving.count) supersets") in \(routine.name)."
            } else {
                let members = resolution.supersetMembers
                if members.count >= 2 {
                    let destination = members[0].group
                    for member in members.dropFirst() where member.group !== destination {
                        moveEntry(member, to: destination, in: routine)
                    }
                }
                if let sets = values.sets {
                    for group in orderedUnique(members.compactMap(\.group)) {
                        group.sets = max(1, sets)
                    }
                }
                let names = members.compactMap { $0.exercise?.name }
                summary = members.count >= 2
                    ? "Superset: \(names.joined(separator: " + ")) in \(routine.name)."
                    : "Changed \(names.first ?? "the block") in \(routine.name)."
            }
            if let uuid = routine.uuid { destinations = [.routine(uuid)] }

        case (.update, .library):
            let subjectNames = resolution.libraries.map(\.name)
            for library in resolution.libraries {
                inverse.librarySnapshots.append(LibrarySnapshot(library: library))
            }
            for library in resolution.libraries {
                if let newName = ChangeFilter.normalized(values.name) { library.name = newName }
                if values.equipment != nil {
                    for member in library.members { library.setMembership(member, false) }
                    for item in resolution.equipment { library.setMembership(item, true) }
                }
            }
            summary = updateSummary(names: subjectNames, values: values)
            destinations = [.equipmentTab]

        case (.delete, .routine):
            for routine in resolution.routines {
                inverse.recreateRoutines.append(RoutineSnapshot(routine: routine))
            }
            let names = resolution.routines.map(\.name)
            for routine in resolution.routines {
                context.delete(routine)
            }
            summary = "Deleted \(names.joined(separator: ", "))."

        case (.delete, .exercise):
            // Built-ins leave the library (the catalog keeps them);
            // customs actually delete, taking their routine entries along
            // rather than leaving ghost rows.
            var removedFromLibrary = 0
            var deleted = 0
            let customIDs = Set(resolution.exercises.filter { !$0.isBuiltIn }.map(\.persistentModelID))
            let affectedRoutines = orderedUnique(resolution.cascadeEntries.compactMap { entry -> Routine? in
                guard let exercise = entry.exercise, customIDs.contains(exercise.persistentModelID) else { return nil }
                return entry.group?.routine
            })
            for routine in affectedRoutines {
                inverse.routineStructures.append(RoutineStructureSnapshot(routine: routine))
            }
            for exercise in resolution.exercises {
                if exercise.isBuiltIn {
                    inverse.exerciseSnapshots.append(ExerciseSnapshot(exercise: exercise))
                    exercise.inLibrary = false
                    removedFromLibrary += 1
                } else {
                    inverse.recreateExercises.append(InterchangeMapping.makeDTO(exercise))
                    for entry in resolution.cascadeEntries where entry.exercise === exercise {
                        removeEntry(entry)
                    }
                    context.delete(exercise)
                    deleted += 1
                }
            }
            var parts: [String] = []
            if deleted > 0 { parts.append("deleted \(deleted) custom\(deleted == 1 ? "" : "s")") }
            if removedFromLibrary > 0 { parts.append("\(removedFromLibrary) built-in\(removedFromLibrary == 1 ? "" : "s") left the library") }
            summary = capitalizedFirst(parts.joined(separator: " · ")) + "."
            destinations = [.exercisesTab]

        case (.delete, .library):
            let all = try context.fetch(FetchDescriptor<EquipmentLibrary>(sortBy: [SortDescriptor(\.order)]))
            let active = EquipmentLibrary.active(in: all)
            let deletingActive = resolution.libraries.contains { $0 === active }
            for library in resolution.libraries {
                inverse.recreateLibraries.append(LibrarySnapshot(library: library, isActive: library === active))
            }
            let names = resolution.libraries.map(\.name)
            for library in resolution.libraries {
                context.delete(library)
            }
            // Deleting the active library re-points the device pointer to
            // a survivor, exactly like the tray's delete does.
            if deletingActive {
                let deleted = Set(resolution.libraries.map(\.uuid))
                if let next = all.first(where: { !deleted.contains($0.uuid) }) {
                    UserDefaults.standard.set(next.uuid.uuidString, forKey: EquipmentLibrary.activeIDKey)
                }
            }
            summary = "Deleted \(names.joined(separator: ", "))."
            destinations = [.equipmentTab]

        default:
            throw EngineError.reason("unsupported change")
        }

        try context.save()
        // Post-save: IDs are permanent now (see `created` above).
        inverse.deleteCreated = created.map(\.persistentModelID)
        afterApply(context)
        return AppliedChange(
            receipt: ChangeReceipt(id: UUID(), summary: summary, destinations: destinations),
            inverse: inverse
        )
    }

    // MARK: - Mutation helpers

    /// Converting an exercise's tracking keeps its defaults coherent:
    /// the new driver metric gets a real default; extra-metric defaults
    /// the profile no longer tracks are dropped (the model setter's own
    /// staleness rule).
    private func convertTracking(of exercise: Exercise, to mode: TrackMode, requestedDuration: Int?, requestedReps: Int?) {
        exercise.metricProfile = mode.profile
        switch mode {
        case .duration:
            exercise.defaultDurationSeconds = requestedDuration ?? exercise.defaultDurationSeconds ?? FallbackTarget.durationSeconds
        case .reps, .weightReps:
            exercise.defaultReps = requestedReps ?? exercise.defaultReps ?? FallbackTarget.reps
        }
        exercise.extraDefaults = exercise.extraDefaults.filter { mode.profile.contains($0.key) }
    }

    /// The entry-level cascade of a tracking conversion: targets follow
    /// the new profile so the set screen drives correctly, sourced from
    /// the exercise's (just-updated) defaults.
    private func convertEntryTargets(_ entry: RoutineExercise, profile: MetricProfile, exercise: Exercise) {
        if profile.tracksReps {
            entry.reps = entry.reps ?? exercise.defaultReps ?? FallbackTarget.reps
        } else {
            entry.reps = nil
            entry.repsUpper = nil
        }
        if profile.contains(.duration) {
            entry.durationSeconds = entry.durationSeconds ?? exercise.defaultDurationSeconds ?? FallbackTarget.durationSeconds
        } else {
            entry.durationSeconds = nil
        }
        if !profile.tracksLoad {
            entry.weight = nil
        }
        entry.extraTargets = entry.extraTargets.filter { profile.contains($0.key) }
    }

    private enum EntryMatch {
        case one(RoutineExercise)
        case many([String])
        case none
    }

    /// The shared entry-in-routine lookup: exact name wins; a UNIQUE
    /// substring match resolves; several substring matches are
    /// ambiguous — the engine asks, it never guesses (the selectNamed
    /// rule; superset edits auto-apply, so a guess would restructure
    /// silently). Several entries of the SAME exercise resolve to the
    /// first in routine order — identical names can't disambiguate
    /// further.
    private func matchEntry(named name: String, in routine: Routine) -> EntryMatch {
        let entries = routine.sortedGroups.flatMap(\.sortedExercises)
        let matches = entries.filter { $0.exercise?.name.localizedCaseInsensitiveContains(name) == true }
        if let exact = matches.first(where: { $0.exercise?.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
            return .one(exact)
        }
        let distinctNames = Array(Set(matches.compactMap { $0.exercise?.name })).sorted()
        if distinctNames.count > 1 { return .many(distinctNames) }
        return matches.first.map { .one($0) } ?? .none
    }

    private func removeEntries(named names: [String], from routine: Routine) throws {
        for name in names {
            switch matchEntry(named: name, in: routine) {
            case .one(let entry):
                removeEntry(entry)
            case .many(let candidates):
                throw EngineError.reason("\(name) matches \(candidates.prefix(4).joined(separator: ", ")) in \(routine.name). Ask the user which.")
            case .none:
                throw EngineError.reason("no \(name) in \(routine.name)")
            }
        }
    }

    /// Deletes one routine entry, cleaning up an emptied group.
    private func removeEntry(_ entry: RoutineExercise) {
        let group = entry.group
        let routine = group?.routine
        context.delete(entry)
        if let group {
            if group.sortedExercises.isEmpty {
                context.delete(group)
            } else {
                group.reindexExercises()
            }
        }
        routine?.reindexGroups()
    }

    private func moveEntry(_ entry: RoutineExercise, to destination: ExerciseGroup?, in routine: Routine) {
        guard let destination else { return }
        let source = entry.group
        entry.order = destination.exercises.count
        entry.group = destination
        destination.reindexExercises()
        if let source, source !== destination {
            if source.sortedExercises.isEmpty {
                context.delete(source)
            } else {
                source.reindexExercises()
            }
        }
        routine.reindexGroups()
    }

    /// Splits every member after the first out of the group — the
    /// superset dissolves into consecutive solo blocks.
    private func dissolve(_ group: ExerciseGroup, in routine: Routine) {
        while group.sortedExercises.count > 1, let last = group.sortedExercises.last {
            routine.splitExercise(last, context: context)
        }
    }

    /// `names` are the PRE-mutation names, captured before the apply
    /// loop, so a rename can say what the thing was called.
    private func updateSummary(names: [String], values: ChangeValues) -> String {
        if let name = ChangeFilter.normalized(values.name), names.count == 1 {
            return names[0].compare(name, options: .caseInsensitive) == .orderedSame
                ? "Renamed to \(name)."
                : "Renamed \(names[0]) to \(name)."
        }
        let subject = names.count == 1 ? names[0] : "\(names.count) items"
        var parts: [String] = []
        if let days = values.scheduleDays {
            parts.append(days.isEmpty ? "schedule cleared" : "scheduled \(RoutineSchedule.weekdays(days).shortLabel)")
        }
        if let mode = values.trackBy { parts.append("tracks \(mode.spokenName) now") }
        if let rest = values.restSeconds { parts.append("rest \(rest) s") }
        if let sets = values.sets { parts.append("\(sets) sets") }
        if values.equipment != nil { parts.append("gear updated") }
        if values.notes != nil { parts.append("notes updated") }
        if let added = values.addExercises, !added.isEmpty { parts.append("added \(added.count)") }
        if let removed = values.removeExercises, !removed.isEmpty { parts.append("removed \(removed.count)") }
        if parts.isEmpty { parts.append("updated") }
        return "\(subject): \(parts.joined(separator: " · "))."
    }

    private func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: - Name matching

    private enum Match<T> {
        case one(T)
        case many([T])
        case none
    }

    /// Exact case-insensitive first; a unique substring match is
    /// accepted; several substring matches are ambiguous.
    private func match<T>(name query: String, in items: [T], by name: KeyPath<T, String>) -> Match<T> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = items.filter { $0[keyPath: name].compare(trimmed, options: .caseInsensitive) == .orderedSame }
        if exact.count == 1 { return .one(exact[0]) }
        if exact.count > 1 { return .many(exact) }
        let partial = items.filter { $0[keyPath: name].localizedCaseInsensitiveContains(trimmed) }
        if partial.count == 1 { return .one(partial[0]) }
        if partial.count > 1 { return .many(partial) }
        return .none
    }

    private func selectNamed<T: AnyObject>(
        spec: ChangeSpec,
        from all: [T],
        by name: KeyPath<T, String>,
        matchesFilter: (T, ChangeFilter) -> Bool
    ) -> Selection<[T]> {
        if !spec.targets.isEmpty {
            var selected: [T] = []
            for target in spec.targets {
                switch match(name: target, in: all, by: name) {
                case .one(let item):
                    selected.append(item)
                case .many(let candidates):
                    let names = candidates.prefix(4).map { $0[keyPath: name] }
                    return .failure("\(target) matches \(names.joined(separator: ", ")). Ask the user which.")
                case .none:
                    return .failure("nothing named \(target)\(closestText(target, in: all.map { $0[keyPath: name] }))")
                }
            }
            return .success(orderedUnique(selected))
        }
        guard let filter = spec.filter, !filter.isEmpty else { return .success([]) }
        return .success(all.filter { matchesFilter($0, filter) })
    }

    /// "Closest: Push Day, Leg Day" — suggestions for a missed name;
    /// empty when nothing is close. FuzzySearch first (typos, glued
    /// words, abbreviations — ranked best-first), then the looser
    /// prefix/substring/shared-word heuristics for partial overlaps
    /// fuzzy's every-word-must-land rule rejects ("Push Workout" still
    /// suggests "Push Day"). Suggestions only — resolution above stays
    /// exact-or-unique-substring, so forgiveness here can never make
    /// the engine touch the wrong thing.
    private func closestText(_ query: String, in names: [String]) -> String {
        var close = FuzzySearch.ranked(names, query: query) { $0 }
        let lowered = query.lowercased()
        if close.isEmpty {
            close = names.filter { candidate in
                let name = candidate.lowercased()
                return name.hasPrefix(String(lowered.prefix(3))) || name.contains(lowered) || lowered.contains(name)
            }
        }
        if close.isEmpty {
            let words = Set(lowered.split(separator: " ").map(String.init))
            close = names.filter { candidate in
                let candidateWords = Set(candidate.lowercased().split(separator: " ").map(String.init))
                return !words.isDisjoint(with: candidateWords)
            }
        }
        guard !close.isEmpty else { return "" }
        return ". Closest: \(close.prefix(3).joined(separator: ", "))"
    }

    private func orderedUnique<T: AnyObject>(_ items: [T]) -> [T] {
        var seen = Set<ObjectIdentifier>()
        return items.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}

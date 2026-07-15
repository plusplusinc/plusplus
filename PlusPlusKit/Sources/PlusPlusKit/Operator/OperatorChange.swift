import Foundation

/// The Operator agent's change vocabulary: one structured statement of
/// intent covering create/update/delete across the library's entity
/// kinds, including bulk filter+transform edits ("every rep-tracked
/// exercise named stretch switches to duration"). The on-device model
/// fills a thin `@Generable` mirror of this in the app target (the macro
/// can't build on Linux); everything from here on down is pure,
/// deterministic, and Linux-tested. The model proposes, the app disposes:
/// specs are validated and resolved by the app's change engine — nothing
/// in this file touches data.
public struct ChangeSpec: Equatable, Codable, Sendable {
    public var operation: ChangeOperation
    public var entity: ChangeEntity
    /// Exact (case-insensitive) names of the items to affect. Empty when
    /// creating, or when `filter` selects the set.
    public var targets: [String]
    /// Selects many items for bulk edits; nil for single named items.
    public var filter: ChangeFilter?
    /// Fields to set; nil for deletes.
    public var values: ChangeValues?

    public init(
        operation: ChangeOperation,
        entity: ChangeEntity,
        targets: [String] = [],
        filter: ChangeFilter? = nil,
        values: ChangeValues? = nil
    ) {
        self.operation = operation
        self.entity = entity
        self.targets = targets
        self.filter = filter
        self.values = values
    }
}

public enum ChangeOperation: String, Codable, Sendable {
    case create, update, delete
}

public enum ChangeEntity: String, Codable, Sendable {
    case routine, exercise, superset, library

    /// "2 routines", "1 exercise" — the shared count-noun rendering.
    public func countNoun(_ count: Int) -> String {
        let plural: String
        switch self {
        case .routine: plural = count == 1 ? "routine" : "routines"
        case .exercise: plural = count == 1 ? "exercise" : "exercises"
        case .superset: plural = count == 1 ? "superset" : "supersets"
        case .library: plural = count == 1 ? "library" : "libraries"
        }
        return "\(count) \(plural)"
    }
}

/// How an exercise is tracked, in the model's vocabulary. Maps onto the
/// common `MetricProfile` shapes; richer profiles (a rower's
/// distance/pace set) match by their dominant read.
public enum TrackMode: String, Codable, Sendable, CaseIterable {
    case reps, duration, weightReps

    /// The profile this mode converts an exercise TO.
    public var profile: MetricProfile {
        switch self {
        case .reps: .repsOnly
        case .duration: .durationOnly
        case .weightReps: .weightReps
        }
    }

    /// Whether an existing profile reads as this mode. The three cases
    /// are disjoint: `reps` is rep-tracked bodyweight work, `weightReps`
    /// is rep-tracked loaded work, `duration` is everything time-driven
    /// that doesn't track reps (including richer cardio profiles).
    public func matches(_ profile: MetricProfile) -> Bool {
        switch self {
        case .reps: profile.tracksReps && !profile.tracksLoad
        case .weightReps: profile.tracksReps && profile.tracksLoad
        case .duration: !profile.tracksReps && profile.contains(.duration)
        }
    }

    /// "weight and reps" reads better aloud than the raw case name —
    /// the shared rendering for digests, previews, and receipts.
    public var spokenName: String {
        self == .weightReps ? "weight and reps" : rawValue
    }
}

/// Bulk selection. All set fields must match (AND semantics); an empty
/// filter selects nothing rather than everything — a bulk edit must SAY
/// what it selects.
public struct ChangeFilter: Equatable, Codable, Sendable {
    /// Case-insensitive substring on the entity name.
    public var nameContains: String?
    public var muscleGroup: MuscleGroup?
    /// Current tracking mode (what the exercise is NOW, pre-change).
    public var trackedBy: TrackMode?
    /// Limit to entries/groups inside this routine (superset edits).
    public var inRoutine: String?

    public init(
        nameContains: String? = nil,
        muscleGroup: MuscleGroup? = nil,
        trackedBy: TrackMode? = nil,
        inRoutine: String? = nil
    ) {
        self.nameContains = nameContains
        self.muscleGroup = muscleGroup
        self.trackedBy = trackedBy
        self.inRoutine = inRoutine
    }

    /// True when no criterion is set (selects nothing).
    public var isEmpty: Bool {
        normalizedNameContains == nil && muscleGroup == nil
            && trackedBy == nil && normalizedInRoutine == nil
    }

    public var normalizedNameContains: String? { Self.normalized(nameContains) }
    public var normalizedInRoutine: String? { Self.normalized(inRoutine) }

    /// Trimmed-or-nil; public because the app-side engine normalizes
    /// names through the same rule.
    public static func normalized(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Fields to set. Which fields apply depends on the entity — validation
/// flags mismatches so the model can course-correct from the digest.
public struct ChangeValues: Equatable, Codable, Sendable {
    public var name: String?
    public var notes: String?
    /// Routine rest between sets, seconds.
    public var restSeconds: Int?
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday). An empty
    /// set clears the schedule; nil leaves it untouched.
    public var scheduleDays: Set<Int>?
    /// Convert the exercise's tracking (the bulk-transform payload).
    public var trackBy: TrackMode?
    public var muscleGroup: MuscleGroup?
    public var reps: Int?
    public var durationSeconds: Int?
    public var weight: Double?
    /// Sets per block (superset edits).
    public var sets: Int?
    /// Equipment names — REPLACES the exercise's gear list, or a
    /// library's membership, wholesale.
    public var equipment: [String]?
    /// Exercise names to append to a routine, in order.
    public var addExercises: [String]?
    public var removeExercises: [String]?

    public init(
        name: String? = nil,
        notes: String? = nil,
        restSeconds: Int? = nil,
        scheduleDays: Set<Int>? = nil,
        trackBy: TrackMode? = nil,
        muscleGroup: MuscleGroup? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        weight: Double? = nil,
        sets: Int? = nil,
        equipment: [String]? = nil,
        addExercises: [String]? = nil,
        removeExercises: [String]? = nil
    ) {
        self.name = name
        self.notes = notes
        self.restSeconds = restSeconds
        self.scheduleDays = scheduleDays
        self.trackBy = trackBy
        self.muscleGroup = muscleGroup
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.weight = weight
        self.sets = sets
        self.equipment = equipment
        self.addExercises = addExercises
        self.removeExercises = removeExercises
    }

    public var isEmpty: Bool {
        name == nil && notes == nil && restSeconds == nil && scheduleDays == nil
            && trackBy == nil && muscleGroup == nil && reps == nil
            && durationSeconds == nil && weight == nil && sets == nil
            && equipment == nil && addExercises == nil && removeExercises == nil
    }
}

extension ChangeSpec {
    /// Model-output leniencies folded into canonical shape before
    /// validation: "create a superset" reads as the update that forms
    /// one; a create whose name landed in `targets` instead of
    /// `values.name` adopts it; target strings are trimmed and blanks
    /// dropped.
    public var normalized: ChangeSpec {
        var spec = self
        spec.targets = targets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if spec.operation == .create, spec.entity == .superset {
            spec.operation = .update
        }
        if spec.operation == .create, spec.values?.name == nil, spec.targets.count == 1 {
            var values = spec.values ?? ChangeValues()
            values.name = spec.targets[0]
            spec.values = values
            spec.targets = []
        }
        return spec
    }

    /// Well-formedness only (no data access): what a spec must carry to
    /// be resolvable at all. Empty means valid. Issue strings are terse
    /// and model-readable — they come back in the INVALID digest.
    public func validationIssues() -> [String] {
        let spec = normalized
        var issues: [String] = []
        let values = spec.values ?? ChangeValues()

        switch spec.operation {
        case .create:
            if ChangeFilter.normalized(values.name) == nil {
                issues.append("create needs values.name")
            }
            if spec.filter != nil {
                issues.append("create takes no filter")
            }
        case .update:
            // Forming a superset needs no field values — naming two or
            // more members IS the change.
            let formsSuperset = spec.entity == .superset && spec.targets.count >= 2
            if values.isEmpty, !formsSuperset {
                issues.append("update needs values")
            }
            if spec.targets.isEmpty, spec.filter?.isEmpty != false {
                issues.append("update needs targets or a filter")
            }
        case .delete:
            if !values.isEmpty {
                issues.append("delete takes no values")
            }
            if spec.targets.isEmpty, spec.filter?.isEmpty != false {
                issues.append("delete needs targets or a filter")
            }
        }

        // Superset edits are scoped to one routine and name their members.
        if spec.entity == .superset {
            if ChangeFilter.normalized(spec.filter?.inRoutine) == nil {
                issues.append("superset changes need filter.inRoutine")
            }
            if spec.operation != .delete, spec.targets.isEmpty {
                issues.append("superset changes need member names in targets")
            }
        }

        // Filter criteria the entity can't evaluate are rejected, never
        // silently ignored — an ignored criterion would widen the
        // selection to everything, the exact opposite of what was asked.
        if let filter = spec.filter {
            if filter.normalizedInRoutine != nil, spec.entity != .superset {
                issues.append("filter.inRoutine applies to superset changes only")
            }
            if filter.muscleGroup != nil, spec.entity != .exercise {
                issues.append("filter.muscleGroup applies to exercises only")
            }
            if filter.trackedBy != nil, spec.entity != .exercise {
                issues.append("filter.trackedBy applies to exercises only")
            }
        }

        // Field applicability — a wrong-entity field is a misunderstanding
        // worth surfacing, not silently dropping.
        if spec.entity != .routine {
            if values.scheduleDays != nil { issues.append("scheduleDays applies to routines only") }
            if values.restSeconds != nil { issues.append("restSeconds applies to routines only") }
            if values.addExercises != nil || values.removeExercises != nil {
                issues.append("addExercises/removeExercises apply to routines only")
            }
        }
        if spec.entity != .exercise {
            if values.trackBy != nil { issues.append("trackBy applies to exercises only") }
            if values.muscleGroup != nil { issues.append("muscleGroup applies to exercises only") }
        }
        if spec.entity != .superset, values.sets != nil {
            issues.append("sets applies to supersets only")
        }
        if spec.entity == .library || spec.entity == .superset {
            if values.reps != nil || values.durationSeconds != nil || values.weight != nil {
                issues.append("reps/duration/weight do not apply to \(spec.entity.rawValue) changes")
            }
        }
        if spec.entity == .routine || spec.entity == .superset, values.equipment != nil {
            issues.append("equipment applies to exercises and libraries only")
        }
        return issues
    }
}

extension ChangeSpec {
    /// Weekday-name parsing for the model's schedule vocabulary:
    /// "mon"/"monday" → 2, matching `Calendar`/`DateComponents.weekday`
    /// (1 = Sunday … 7 = Saturday). Hand-mapped — no locale involved.
    /// Unknown names return nil so the caller can flag them rather than
    /// silently scheduling the wrong day. (Rendering the other way is
    /// NOT defined here: `RoutineSchedule.shortLabel` is the one schedule
    /// vocabulary every surface shares.)
    public static func weekdayNumber(from name: String) -> Int? {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sun", "sunday": 1
        case "mon", "monday": 2
        case "tue", "tues", "tuesday": 3
        case "wed", "weds", "wednesday": 4
        case "thu", "thur", "thurs", "thursday": 5
        case "fri", "friday": 6
        case "sat", "saturday": 7
        default: nil
        }
    }
}

import Foundation

public struct ValidationIssue: Equatable, Sendable, CustomStringConvertible {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { "\(path): \(message)" }
}

/// Semantic validation beyond what Codable enforces — the checks `plusplus
/// lint` and the app's importer share. Returns all issues rather than
/// throwing on the first, so tools can report a complete list.
public enum InterchangeValidator {
    /// Metrics that ride dedicated fields — an extras dictionary carrying
    /// them would create two competing values for one quantity.
    private static let dedicatedMetrics: Set<String> = [
        WorkoutMetric.weight.rawValue, WorkoutMetric.reps.rawValue,
        WorkoutMetric.duration.rawValue, WorkoutMetric.rest.rawValue,
    ]

    /// Shared checks for extraDefaults/extraTargets/extraActuals: keys
    /// must come from the curated vocabulary (this is what `plusplus
    /// lint` exists for — catching a hand-typed "resistence" before it
    /// silently tracks nothing), must not shadow a dedicated field, and
    /// values must be finite and non-negative.
    private static func validateExtras(_ extras: [String: Double]?, field: String, path: String, issues: inout [ValidationIssue]) {
        guard let extras else { return }
        for (key, value) in extras.sorted(by: { $0.key < $1.key }) {
            if dedicatedMetrics.contains(key) {
                issues.append(.init(path: path, message: "\(field).\(key) belongs in its dedicated field"))
            } else if WorkoutMetric(rawValue: key) == nil {
                issues.append(.init(path: path, message: "\(field).\(key) is not a known metric"))
            }
            if !value.isFinite || value < 0 {
                issues.append(.init(path: path, message: "\(field).\(key) value \(value) must be finite and non-negative"))
            }
        }
    }

    /// - Parameter knownExerciseNames: lowercased names of exercises that
    ///   exist in the target library (the app's built-ins + already-imported
    ///   exercises, or a repo's exercise files). When provided, a routine
    ///   reference resolving against neither the bundle NOR this set is
    ///   flagged. When `nil` (the default), reference existence is NOT checked
    ///   — a bundle legitimately omits unannotated built-ins (the export
    ///   policy: built-ins ship with the app, only annotated ones travel), so
    ///   guessing from the bundle alone false-positives. The app importer
    ///   resolves references against the live store and skips any that don't.
    public static func validate(
        _ bundle: ExportBundle,
        knownExerciseNames: Set<String>? = nil
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        var exerciseNames: Set<String> = []
        for exercise in bundle.exercises {
            let path = "exercises[\(exercise.name)]"
            let key = exercise.name.lowercased().trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                issues.append(.init(path: path, message: "exercise name is empty"))
            }
            if !exerciseNames.insert(key).inserted {
                issues.append(.init(path: path, message: "duplicate exercise name"))
            }
            // Default targets (#187) — same bounds as routine entries.
            if let reps = exercise.defaultReps, !(1...100).contains(reps) {
                issues.append(.init(path: path, message: "defaultReps \(reps) outside 1...100"))
            }
            if let upper = exercise.defaultRepsUpper {
                if let reps = exercise.defaultReps {
                    if upper <= reps {
                        issues.append(.init(path: path, message: "defaultRepsUpper \(upper) must exceed defaultReps \(reps)"))
                    }
                } else {
                    issues.append(.init(path: path, message: "defaultRepsUpper without defaultReps"))
                }
            }
            if let weight = exercise.defaultWeight, weight < 0 {
                issues.append(.init(path: path, message: "negative defaultWeight"))
            }
            if let duration = exercise.defaultDurationSeconds, duration <= 0 {
                issues.append(.init(path: path, message: "non-positive defaultDurationSeconds"))
            }
            // Flexible metrics: the profile must speak the curated
            // vocabulary, contain a work metric, and agree with the
            // legacy exerciseType old readers still trust.
            if let metrics = exercise.metrics {
                var parsed: [WorkoutMetric] = []
                for key in metrics {
                    if key == WorkoutMetric.rest.rawValue {
                        issues.append(.init(path: path, message: "metrics may not include rest (block configuration, not a tracked metric)"))
                    } else if let metric = WorkoutMetric(rawValue: key) {
                        parsed.append(metric)
                    } else {
                        issues.append(.init(path: path, message: "metrics.\(key) is not a known metric"))
                    }
                }
                let profile = MetricProfile(parsed)
                if !profile.isValid {
                    issues.append(.init(path: path, message: "metrics must include a work metric (reps, distance, calories, or duration)"))
                }
                if profile.isValid, profile.legacyType != exercise.exerciseType {
                    issues.append(.init(path: path, message: "exerciseType \(exercise.exerciseType.rawValue) disagrees with metrics (expected \(profile.legacyType.rawValue))"))
                }
            }
            validateExtras(exercise.extraDefaults, field: "extraDefaults", path: path, issues: &issues)
        }

        for routine in bundle.routines {
            let path = "routines[\(routine.name)]"
            if routine.name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(.init(path: path, message: "routine name is empty"))
            }
            if !(15...600).contains(routine.restSeconds) {
                issues.append(.init(path: path, message: "restSeconds \(routine.restSeconds) outside 15...600"))
            }
            for (groupIndex, group) in routine.groups.enumerated() {
                let groupPath = "\(path).groups[\(groupIndex)]"
                if group.exercises.isEmpty {
                    issues.append(.init(path: groupPath, message: "group has no exercises"))
                }
                if !(1...20).contains(group.sets) {
                    issues.append(.init(path: groupPath, message: "sets \(group.sets) outside 1...20"))
                }
                if let rest = group.restSeconds, !(15...600).contains(rest) {
                    issues.append(.init(path: groupPath, message: "restSeconds \(rest) outside 15...600"))
                }
                for entry in group.exercises {
                    let entryPath = "\(groupPath).\(entry.exercise)"
                    // Reference existence needs the target library, which this
                    // pure validator can't see — so it's checked only when the
                    // caller supplies `knownExerciseNames`. Otherwise a bundle
                    // that omits unannotated built-ins (the export policy) would
                    // false-positive; the importer resolves against the live
                    // store instead.
                    if let known = knownExerciseNames {
                        let name = entry.exercise.lowercased()
                        if !exerciseNames.contains(name), !known.contains(name) {
                            issues.append(.init(path: entryPath, message: "unresolved exercise reference (not in bundle or the target library)"))
                        }
                    }
                    if let reps = entry.reps, !(1...100).contains(reps) {
                        issues.append(.init(path: entryPath, message: "reps \(reps) outside 1...100"))
                    }
                    if let upper = entry.repsUpper {
                        if let reps = entry.reps {
                            if upper <= reps {
                                issues.append(.init(path: entryPath, message: "repsUpper \(upper) must exceed reps \(reps)"))
                            }
                        } else {
                            issues.append(.init(path: entryPath, message: "repsUpper without reps"))
                        }
                    }
                    if let weight = entry.weight, weight < 0 {
                        issues.append(.init(path: entryPath, message: "negative weight"))
                    }
                    if let duration = entry.durationSeconds, duration <= 0 {
                        issues.append(.init(path: entryPath, message: "non-positive durationSeconds"))
                    }
                    validateExtras(entry.extraTargets, field: "extraTargets", path: entryPath, issues: &issues)
                }
            }
        }

        var equipmentNames: Set<String> = []
        for item in bundle.equipment ?? [] {
            let path = "equipment[\(item.name)]"
            let key = item.name.lowercased().trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                issues.append(.init(path: path, message: "equipment name is empty"))
            }
            if !equipmentNames.insert(key).inserted {
                issues.append(.init(path: path, message: "duplicate equipment name"))
            }
            if let step = item.weightStep, !step.isFinite || step <= 0 {
                issues.append(.init(path: path, message: "weightStep \(step) must be finite and positive"))
            }
            // Same curated vocabulary as exercise metrics, but no
            // work-metric requirement: this is a suggestion set, not a
            // trackable profile.
            for key in item.metrics ?? [] {
                if key == WorkoutMetric.rest.rawValue {
                    issues.append(.init(path: path, message: "metrics may not include rest (block configuration, not a tracked metric)"))
                } else if WorkoutMetric(rawValue: key) == nil {
                    issues.append(.init(path: path, message: "metrics.\(key) is not a known metric"))
                }
            }
        }

        var libraryNames: Set<String> = []
        for library in bundle.equipmentLibraries ?? [] {
            let path = "equipmentLibraries[\(library.name)]"
            let key = library.name.lowercased().trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                issues.append(.init(path: path, message: "library name is empty"))
            }
            if !libraryNames.insert(key).inserted {
                issues.append(.init(path: path, message: "duplicate library name"))
            }
            // Gear names are free-form (customs are legal and importers
            // create them), but an empty string is always a mistake.
            for name in library.equipment where name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(.init(path: path, message: "equipment entry is empty"))
            }
        }

        for session in bundle.sessions {
            let path = "sessions[\(session.routineName) @ \(session.startedAt)]"
            if let endedAt = session.endedAt, endedAt < session.startedAt {
                issues.append(.init(path: path, message: "endedAt precedes startedAt"))
            }
            var seenOrders: Set<Int> = []
            for set in session.sets {
                if set.exerciseName.trimmingCharacters(in: .whitespaces).isEmpty {
                    issues.append(.init(path: path, message: "set \(set.order) has empty exerciseName"))
                }
                if !seenOrders.insert(set.order).inserted {
                    issues.append(.init(path: path, message: "duplicate set order \(set.order)"))
                }
                if let rest = set.restSecondsOverride, !(15...600).contains(rest) {
                    issues.append(.init(path: path, message: "set \(set.order) restSecondsOverride \(rest) outside 15...600"))
                }
                validateExtras(set.extraTargets, field: "extraTargets", path: "\(path).sets[\(set.order)]", issues: &issues)
                validateExtras(set.extraActuals, field: "extraActuals", path: "\(path).sets[\(set.order)]", issues: &issues)
            }
        }

        return issues
    }
}

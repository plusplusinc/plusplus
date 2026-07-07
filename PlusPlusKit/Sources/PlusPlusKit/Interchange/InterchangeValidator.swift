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
    public static func validate(_ bundle: ExportBundle) -> [ValidationIssue] {
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
                for entry in group.exercises {
                    let entryPath = "\(groupPath).\(entry.exercise)"
                    // References may resolve against the bundle OR the app's
                    // built-in library, which this validator can't see — so a
                    // missing reference is only reported when the bundle
                    // declares exercises at all and the name isn't among them.
                    if !bundle.exercises.isEmpty,
                       !exerciseNames.contains(entry.exercise.lowercased()) {
                        issues.append(.init(path: entryPath, message: "unresolved exercise reference (not in bundle; must exist in the target library)"))
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
                }
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
            }
        }

        return issues
    }
}

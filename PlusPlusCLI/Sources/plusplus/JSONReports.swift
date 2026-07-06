import Foundation
import PlusPlusKit

/// Machine-readable mirrors of the CLI's text output (`--json`), for agents
/// and the MCP server (#25). Encoded via `InterchangeCodec` so output is
/// deterministic: sorted keys, ISO-8601 dates.
struct LintReport: Codable, Equatable {
    struct Counts: Codable, Equatable {
        var exercises: Int
        var workouts: Int
        var sessions: Int
    }

    struct Issue: Codable, Equatable {
        var path: String
        var message: String
    }

    var valid: Bool
    var counts: Counts
    var issues: [Issue]

    init(bundle: ExportBundle, issues: [ValidationIssue]) {
        valid = issues.isEmpty
        counts = Counts(
            exercises: bundle.exercises.count,
            workouts: bundle.workouts.count,
            sessions: bundle.sessions.count
        )
        self.issues = issues.map { Issue(path: $0.path, message: $0.message) }
    }
}

struct StatsReport: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var name: String
        var sessions: Int
        var sets: Int
        var reps: Int
        var maxWeight: Double?
        var maxDurationSeconds: Int?
        var lastPerformed: Date?
    }

    /// What maxWeight numbers are denominated in (the bundle's declared
    /// units; lb when undeclared).
    var units: WeightUnit
    var exercises: [Entry]

    init(stats: [ExerciseStats], units: WeightUnit = .lb) {
        self.units = units
        exercises = stats.map {
            Entry(
                name: $0.name,
                sessions: $0.sessionCount,
                sets: $0.setCount,
                reps: $0.totalReps,
                maxWeight: $0.maxWeight,
                maxDurationSeconds: $0.maxDurationSeconds,
                lastPerformed: $0.lastPerformed
            )
        }
    }
}

func printJSON<T: Encodable>(_ value: T) throws {
    let data = try InterchangeCodec.encode(value)
    print(String(decoding: data, as: UTF8.self))
}

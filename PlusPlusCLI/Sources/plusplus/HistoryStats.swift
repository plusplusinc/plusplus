import Foundation
import PlusPlusKit

/// Per-exercise aggregates over completed sets — the engine behind
/// `plusplus stats`. Pure so it's trivially testable.
struct ExerciseStats: Equatable {
    let name: String
    var sessionCount = 0
    var setCount = 0
    var totalReps = 0
    var maxWeight: Double?
    var maxDurationSeconds: Int?
    var lastPerformed: Date?

    var bestDescription: String {
        if let maxWeight, maxWeight > 0 {
            return "\(WorkoutMetric.weight.formatted(maxWeight)) lb"
        }
        if let maxDurationSeconds {
            return "\(maxDurationSeconds) sec"
        }
        return "—"
    }
}

enum HistoryStats {
    static func compute(from sessions: [SessionDTO]) -> [ExerciseStats] {
        var byName: [String: ExerciseStats] = [:]

        for session in sessions {
            var exercisesInSession: Set<String> = []
            for set in session.sets where set.completedAt != nil {
                var stats = byName[set.exerciseName] ?? ExerciseStats(name: set.exerciseName)
                stats.setCount += 1
                stats.totalReps += set.actualReps ?? 0
                if let weight = set.actualWeight {
                    stats.maxWeight = max(stats.maxWeight ?? 0, weight)
                }
                if let duration = set.actualDuration {
                    stats.maxDurationSeconds = max(stats.maxDurationSeconds ?? 0, duration)
                }
                if stats.lastPerformed.map({ $0 < session.startedAt }) ?? true {
                    stats.lastPerformed = session.startedAt
                }
                if exercisesInSession.insert(set.exerciseName).inserted {
                    stats.sessionCount += 1
                }
                byName[set.exerciseName] = stats
            }
        }

        return byName.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Fixed-width text table; dates in UTC for determinism.
    static func table(for stats: [ExerciseStats]) -> String {
        var rows: [[String]] = [["Exercise", "Sessions", "Sets", "Reps", "Best", "Last"]]
        for entry in stats {
            let last = entry.lastPerformed.map { FileLayout.utcDateParts(of: $0).dateStamp } ?? "—"
            rows.append([
                entry.name,
                String(entry.sessionCount),
                String(entry.setCount),
                String(entry.totalReps),
                entry.bestDescription,
                last,
            ])
        }

        var widths = [Int](repeating: 0, count: rows[0].count)
        for row in rows {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }
        return rows.map { row in
            row.enumerated()
                .map { index, cell in cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
                .trimmingCharacters(in: .whitespaces)
        }
        .joined(separator: "\n")
    }
}

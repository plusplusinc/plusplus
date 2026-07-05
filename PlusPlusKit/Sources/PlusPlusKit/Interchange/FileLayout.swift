import Foundation

/// The per-entity repo layout as pure path/content math — shared by the CLI
/// (writing to disk) and the app's future GitHub sync (#23, writing via API).
/// Neither transport should invent paths on its own.
public enum FileLayout {
    public static let exercisesDirectory = "program/exercises"
    public static let workoutsDirectory = "program/workouts"
    public static let historyDirectory = "history"

    public static func exercisePath(for name: String) -> String {
        "\(exercisesDirectory)/\(Slug.make(name)).json"
    }

    public static func workoutPath(for name: String) -> String {
        "\(workoutsDirectory)/\(Slug.make(name)).json"
    }

    /// Template files (exercises + workouts) for a bundle: repo-relative
    /// path → canonical bytes. Templates overwrite on write; sessions go
    /// through `sessionPlacement` because they're append-only.
    public static func templateFiles(for bundle: ExportBundle) throws -> [(path: String, data: Data)] {
        var files: [(path: String, data: Data)] = []
        for exercise in bundle.exercises {
            files.append((
                exercisePath(for: exercise.name),
                try InterchangeCodec.encode(ExerciseDocument(exercise: exercise))
            ))
        }
        for workout in bundle.workouts {
            files.append((
                workoutPath(for: workout.name),
                try InterchangeCodec.encode(WorkoutDocument(workout: workout))
            ))
        }
        return files
    }

    /// Where a session lands, honoring append-only semantics: the first free
    /// dated path, or the existing path when identical content is already
    /// there (`alreadyPresent`), or a numbered suffix when a different
    /// same-day session occupies the base name. `existingContent` abstracts
    /// the transport (disk for the CLI, remote file map for sync).
    public static func sessionPlacement(
        for session: SessionDTO,
        existingContent: (String) -> Data?
    ) throws -> (path: String, data: Data, alreadyPresent: Bool) {
        let data = try InterchangeCodec.encode(SessionDocument(session: session))
        let (year, stamp) = utcDateParts(of: session.startedAt)
        let base = "\(historyDirectory)/\(year)/\(stamp)-\(Slug.make(session.workoutName))"

        var attempt = 1
        while true {
            let path = attempt == 1 ? "\(base).json" : "\(base)-\(attempt).json"
            guard let existing = existingContent(path) else {
                return (path, data, false)
            }
            if existing == data {
                return (path, data, true)
            }
            attempt += 1
        }
    }

    /// ("2026", "2026-07-05") in UTC — file names must be identical no
    /// matter which machine or time zone produces them.
    public static func utcDateParts(of date: Date) -> (year: String, dateStamp: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", parts.year ?? 0)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return (year, stamp)
    }
}

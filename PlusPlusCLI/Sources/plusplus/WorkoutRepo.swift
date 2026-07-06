import Foundation
import PlusPlusKit

/// Reads and writes the per-entity repo layout (docs/PLATFORM.md):
///
///     program/exercises/<slug>.json    ExerciseDocument
///     program/workouts/<slug>.json     WorkoutDocument
///     history/<YYYY>/<date>-<slug>.json SessionDocument (append-only)
struct WorkoutRepo {
    enum RepoError: Error, CustomStringConvertible {
        case notARepo(String)
        case unreadable(String, Error)

        var description: String {
            switch self {
            case .notARepo(let path):
                "\(path) doesn't look like a workout repo (no program/ or history/ directory) or a bundle file"
            case .unreadable(let path, let error):
                "\(path): \(error)"
            }
        }
    }

    struct WriteSummary: Equatable {
        var written: [String] = []
        var skipped: [String] = []
    }

    let root: URL
    private let fileManager = FileManager.default

    var exercisesDirectory: URL {
        root.appendingPathComponent("program").appendingPathComponent("exercises")
    }
    var workoutsDirectory: URL {
        root.appendingPathComponent("program").appendingPathComponent("workouts")
    }
    var historyDirectory: URL {
        root.appendingPathComponent("history")
    }

    var looksLikeRepo: Bool {
        fileManager.fileExists(atPath: root.appendingPathComponent("program").path)
            || fileManager.fileExists(atPath: historyDirectory.path)
    }

    // MARK: - Reading

    func loadBundle() throws -> ExportBundle {
        guard looksLikeRepo else {
            throw RepoError.notARepo(root.path)
        }
        let exercises: [ExerciseDTO] = try loadDocuments(in: exercisesDirectory) {
            (document: ExerciseDocument) in document.exercise
        }
        let workouts: [WorkoutDTO] = try loadDocuments(in: workoutsDirectory) {
            (document: WorkoutDocument) in document.workout
        }
        var sessions: [SessionDTO] = []
        for yearDirectory in try subdirectories(of: historyDirectory) {
            sessions += try loadDocuments(in: yearDirectory) {
                (document: SessionDocument) in document.session
            }
        }
        return ExportBundle(exercises: exercises, workouts: workouts, sessions: sessions)
    }

    private func subdirectories(of url: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadDocuments<Document: Decodable, DTO>(
        in directory: URL,
        unwrap: (Document) -> DTO
    ) throws -> [DTO] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { url in
            do {
                let data = try Data(contentsOf: url)
                return unwrap(try InterchangeCodec.decode(Document.self, from: data))
            } catch {
                throw RepoError.unreadable(url.path, error)
            }
        }
    }

    // MARK: - Writing

    /// Writes a bundle into the layout. Templates (exercises, workouts) are
    /// overwritten; sessions are append-only — an existing file with
    /// identical content counts as skipped, a same-day/same-workout session
    /// with different content gets a numbered suffix.
    func write(bundle: ExportBundle) throws -> WriteSummary {
        var summary = WriteSummary()

        try fileManager.createDirectory(at: exercisesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workoutsDirectory, withIntermediateDirectories: true)

        for exercise in bundle.exercises {
            let url = exercisesDirectory.appendingPathComponent("\(Slug.make(exercise.name)).json")
            try overwrite(InterchangeCodec.encode(ExerciseDocument(exercise: exercise)), at: url, summary: &summary)
        }
        for workout in bundle.workouts {
            let url = workoutsDirectory.appendingPathComponent("\(Slug.make(workout.name)).json")
            try overwrite(InterchangeCodec.encode(WorkoutDocument(workout: workout)), at: url, summary: &summary)
        }
        for session in bundle.sessions {
            try appendSession(session, summary: &summary)
        }
        return summary
    }

    private func overwrite(_ data: Data, at url: URL, summary: inout WriteSummary) throws {
        if fileManager.fileExists(atPath: url.path),
           let existing = try? Data(contentsOf: url), existing == data {
            summary.skipped.append(relativePath(of: url))
            return
        }
        try data.write(to: url)
        summary.written.append(relativePath(of: url))
    }

    private func appendSession(_ session: SessionDTO, summary: inout WriteSummary) throws {
        let (year, dateStamp) = Self.utcDateParts(of: session.startedAt)
        let directory = historyDirectory.appendingPathComponent(year)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = "\(dateStamp)-\(Slug.make(session.workoutName))"
        let data = try InterchangeCodec.encode(SessionDocument(session: session))

        var attempt = 1
        while true {
            let name = attempt == 1 ? "\(base).json" : "\(base)-\(attempt).json"
            let url = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: url.path) {
                try data.write(to: url)
                summary.written.append(relativePath(of: url))
                return
            }
            if let existing = try? Data(contentsOf: url), existing == data {
                summary.skipped.append(relativePath(of: url))
                return
            }
            attempt += 1
        }
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    /// ("2026", "2026-07-05") in UTC — deterministic file names regardless
    /// of the machine's time zone.
    static func utcDateParts(of date: Date) -> (year: String, dateStamp: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", parts.year ?? 0)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return (year, stamp)
    }
}

/// Loads either a workout repo directory or a single bundle file — every
/// read-only command accepts both.
enum BundleSource {
    static func load(path: String) throws -> ExportBundle {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            let data = try Data(contentsOf: url)
            return try InterchangeCodec.decode(ExportBundle.self, from: data)
        }
        return try WorkoutRepo(root: url).loadBundle()
    }
}

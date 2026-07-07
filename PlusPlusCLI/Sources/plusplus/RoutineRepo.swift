import Foundation
import PlusPlusKit

/// Reads and writes the per-entity repo layout (docs/PLATFORM.md):
///
///     program/exercises/<slug>.json    ExerciseDocument
///     program/routines/<slug>.json     RoutineDocument
///     history/<YYYY>/<date>-<slug>.json SessionDocument (append-only)
struct RoutineRepo {
    enum RepoError: Error, CustomStringConvertible {
        case notARepo(String)
        case unreadable(String, Error)

        var description: String {
            switch self {
            case .notARepo(let path):
                "\(path) doesn't look like a routine repo (no program/ or history/ directory) or a bundle file"
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
        root.appendingPathComponent(FileLayout.exercisesDirectory)
    }
    var routinesDirectory: URL {
        root.appendingPathComponent(FileLayout.routinesDirectory)
    }
    var historyDirectory: URL {
        root.appendingPathComponent(FileLayout.historyDirectory)
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
        let routines: [RoutineDTO] = try loadDocuments(in: routinesDirectory) {
            (document: RoutineDocument) in document.routine
        }
        var sessions: [SessionDTO] = []
        for yearDirectory in try subdirectories(of: historyDirectory) {
            sessions += try loadDocuments(in: yearDirectory) {
                (document: SessionDocument) in document.session
            }
        }
        return ExportBundle(exercises: exercises, routines: routines, sessions: sessions)
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

    /// Writes a bundle into the layout. Templates (exercises, routines) are
    /// overwritten; sessions are append-only — an existing file with
    /// identical content counts as skipped, a same-day/same-routine session
    /// with different content gets a numbered suffix.
    func write(bundle: ExportBundle) throws -> WriteSummary {
        var summary = WriteSummary()

        for (path, data) in try FileLayout.templateFiles(for: bundle) {
            if contents(atRelativePath: path) == data {
                summary.skipped.append(path)
                continue
            }
            try writeFile(data, atRelativePath: path)
            summary.written.append(path)
        }

        for session in bundle.sessions {
            let placement = try FileLayout.sessionPlacement(for: session) { path in
                contents(atRelativePath: path)
            }
            if placement.alreadyPresent {
                summary.skipped.append(placement.path)
            } else {
                try writeFile(placement.data, atRelativePath: placement.path)
                summary.written.append(placement.path)
            }
        }
        return summary
    }

    private func contents(atRelativePath path: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(path))
    }

    private func writeFile(_ data: Data, atRelativePath path: String) throws {
        let url = root.appendingPathComponent(path)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

/// Loads either a routine repo directory or a single bundle file — every
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
        return try RoutineRepo(root: url).loadBundle()
    }
}

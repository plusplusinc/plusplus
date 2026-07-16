import Foundation

/// The per-entity repo layout as pure path/content math — shared by the CLI
/// (writing to disk) and the app's future GitHub sync (#23, writing via API).
/// Neither transport should invent paths on its own.
public enum FileLayout {
    public static let exercisesDirectory = "program/exercises"
    public static let routinesDirectory = "program/routines"
    public static let equipmentDirectory = "program/equipment"
    public static let equipmentLibrariesDirectory = "program/equipment-libraries"
    public static let historyDirectory = "history"

    public static func exercisePath(for name: String) -> String {
        "\(exercisesDirectory)/\(Slug.make(name)).json"
    }

    public static func routinePath(for name: String) -> String {
        "\(routinesDirectory)/\(Slug.make(name)).json"
    }

    public static func equipmentPath(for name: String) -> String {
        "\(equipmentDirectory)/\(Slug.make(name)).json"
    }

    public static func equipmentLibraryPath(for name: String) -> String {
        "\(equipmentLibrariesDirectory)/\(Slug.make(name)).json"
    }

    /// Template files (exercises + routines) for a bundle: repo-relative
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
        for routine in bundle.routines {
            files.append((
                routinePath(for: routine.name),
                try InterchangeCodec.encode(RoutineDocument(routine: routine))
            ))
        }
        for item in bundle.equipment ?? [] {
            files.append((
                equipmentPath(for: item.name),
                try InterchangeCodec.encode(EquipmentDocument(equipment: item))
            ))
        }
        for library in bundle.equipmentLibraries ?? [] {
            files.append((
                equipmentLibraryPath(for: library.name),
                try InterchangeCodec.encode(EquipmentLibraryDocument(library: library))
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
        let base = "\(historyDirectory)/\(year)/\(stamp)-\(Slug.make(session.routineName))"

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

    /// The GPX route sidecar twin of a session file (#378): same directory,
    /// same basename, `.gpx`. Pairing is this naming convention, not a JSON
    /// field — computable from a directory listing, and the append-only
    /// session file never needs a link rewritten. Numbered `-2` suffixes
    /// pair automatically because both names derive from one
    /// `sessionPlacement` result.
    public static func routeSidecarPath(forSessionPath path: String) -> String {
        path.hasSuffix(".json") ? String(path.dropLast(".json".count)) + ".gpx" : path + ".gpx"
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

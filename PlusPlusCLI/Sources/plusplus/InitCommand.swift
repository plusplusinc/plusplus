import ArgumentParser
import Foundation
import PlusPlusKit

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new routine repo (program/ + history/ + README).",
        discussion: """
        Creates the layout the app, the CLI, and agents all share. Run it in \
        an empty directory (a fresh git repo is fine), commit, and start \
        adding exercises and routines — `plusplus lint` keeps you honest.
        """
    )

    @Argument(help: "Directory to scaffold (created if missing).")
    var path: String = "."

    @Flag(name: .long, help: "Include a commented example exercise and routine.")
    var example = false

    @Flag(name: .long, help: "Scaffold even if the directory isn't empty.")
    var force = false

    func run() throws {
        let root = URL(fileURLWithPath: path)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        if !force, try !Self.isEffectivelyEmpty(root) {
            print("error: \(path) is not empty — pass --force to scaffold anyway")
            throw ExitCode.failure
        }

        var written: [String] = []
        for file in try Self.scaffoldFiles(example: example) {
            let target = root.appendingPathComponent(file.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { continue }
            try file.data.write(to: target)
            written.append(file.path)
        }

        for line in written {
            print("wrote   \(line)")
        }
        print("Initialized routine repo at \(path) — `git init && git add .` if it isn't one already.")
    }

    /// Empty enough to scaffold: nothing visible. Dotfiles (.git of a fresh
    /// clone, .DS_Store) don't count as content.
    static func isEffectivelyEmpty(_ root: URL) throws -> Bool {
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        return entries.allSatisfy { $0.hasPrefix(".") }
    }

    /// Everything `init` writes, as pure path/bytes pairs so tests can
    /// assert on the plan without touching disk.
    static func scaffoldFiles(example: Bool) throws -> [(path: String, data: Data)] {
        var files: [(path: String, data: Data)] = [
            ("README.md", Data(readme.utf8)),
            (".gitattributes", Data("*.json text eol=lf\n".utf8)),
            ("\(FileLayout.exercisesDirectory)/.gitkeep", Data()),
            ("\(FileLayout.routinesDirectory)/.gitkeep", Data()),
            ("\(FileLayout.historyDirectory)/.gitkeep", Data()),
        ]

        if example {
            let exercise = ExerciseDTO(
                name: "Push-Up",
                muscleGroup: .chest,
                exerciseType: .weightReps,
                equipment: [],
                notes: "Example exercise — edit or delete freely."
            )
            let routine = RoutineDTO(name: "Example Day", restSeconds: 90, groups: [
                .init(sets: 3, exercises: [.init(exercise: "Push-Up", reps: 10)])
            ])
            files.append((
                FileLayout.exercisePath(for: exercise.name),
                try InterchangeCodec.encode(ExerciseDocument(exercise: exercise))
            ))
            files.append((
                FileLayout.routinePath(for: routine.name),
                try InterchangeCodec.encode(RoutineDocument(routine: routine))
            ))
        }
        return files
    }

    private static let readme = """
    # My Routines

    Training data for [PlusPlus](https://github.com/mrdavidjcole/plusplus), \
    stored as versioned JSON (interchange schema v\(Interchange.schemaVersion)).

    ## Layout

    ```
    program/exercises/   one exercise per file
    program/routines/    one routine per file
    history/YYYY/        finished sessions — append-only, never rewritten
    ```

    ## Working on it

    - Edit anything under `program/` freely; run `plusplus lint` before committing
    - `plusplus stats` summarizes training history
    - Don't edit or rename files under `history/` — they're the record

    """
}

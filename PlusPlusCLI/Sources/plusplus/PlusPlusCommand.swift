import ArgumentParser
import Foundation
import PlusPlusKit

@main
struct PlusPlusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plusplus",
        abstract: "Manage PlusPlus workout data as files (interchange schema v\(Interchange.schemaVersion)).",
        discussion: """
        Operates on a workout repo (program/ + history/, usually a git clone) \
        or on a single export bundle from the iPhone app. Transport and auth \
        are git's job — this tool never talks to GitHub.
        """,
        subcommands: [InitCommand.self, Lint.self, Stats.self, ImportCommand.self, ExportCommand.self]
    )
}

/// Prints every validation issue and exits nonzero — the shared gate all
/// commands run before trusting a bundle.
func requireValid(_ bundle: PlusPlusKit.ExportBundle) throws {
    let issues = InterchangeValidator.validate(bundle)
    guard issues.isEmpty else {
        for issue in issues {
            print("error: \(issue)")
        }
        throw ExitCode.failure
    }
}

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate a workout repo or bundle file against schema v\(Interchange.schemaVersion)."
    )

    @Argument(help: "Path to a workout repo directory or a bundle .json file.")
    var path: String = "."

    @Flag(name: .long, help: "Emit a machine-readable JSON report instead of text.")
    var json = false

    func run() throws {
        let bundle = try BundleSource.load(path: path)
        let issues = InterchangeValidator.validate(bundle)

        if json {
            try printJSON(LintReport(bundle: bundle, issues: issues))
            guard issues.isEmpty else { throw ExitCode.failure }
            return
        }

        guard issues.isEmpty else {
            for issue in issues {
                print("error: \(issue)")
            }
            throw ExitCode.failure
        }
        print("OK — \(bundle.exercises.count) exercises, \(bundle.workouts.count) workouts, \(bundle.sessions.count) sessions")
    }
}

struct Stats: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Per-exercise history stats (sessions, sets, reps, best, last performed)."
    )

    @Argument(help: "Path to a workout repo directory or a bundle .json file.")
    var path: String = "."

    @Option(name: .long, help: "Only show one exercise (case-insensitive name match).")
    var exercise: String?

    @Flag(name: .long, help: "Emit machine-readable JSON instead of the table.")
    var json = false

    func run() throws {
        let bundle = try BundleSource.load(path: path)
        var stats = HistoryStats.compute(from: bundle.sessions)
        if let exercise {
            stats = stats.filter { $0.name.lowercased() == exercise.lowercased() }
            if stats.isEmpty {
                if json {
                    try printJSON(StatsReport(stats: []))
                } else {
                    print("No completed sets found for \"\(exercise)\".")
                }
                throw ExitCode.failure
            }
        }
        if json {
            try printJSON(StatsReport(stats: stats))
            return
        }
        if stats.isEmpty {
            print("No history yet.")
            return
        }
        print(HistoryStats.table(for: stats))
    }
}

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Write an app export bundle into the per-file repo layout.",
        discussion: "Templates are overwritten; history is append-only. Typical use: bootstrap or refresh a workout repo from the iPhone app's Export Data file, then review and commit with git."
    )

    @Argument(help: "The bundle .json exported from the app.")
    var bundlePath: String

    @Option(name: .long, help: "Workout repo root to write into.")
    var into: String = "."

    func run() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: bundlePath))
        let bundle = try InterchangeCodec.decode(PlusPlusKit.ExportBundle.self, from: data)
        try requireValid(bundle)

        let summary = try WorkoutRepo(root: URL(fileURLWithPath: into)).write(bundle: bundle)
        for path in summary.written {
            print("wrote   \(path)")
        }
        print("\(summary.written.count) written, \(summary.skipped.count) unchanged — review with `git status`, then commit.")
    }
}

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Combine a workout repo into a single bundle file (for the app's Import Data)."
    )

    @Argument(help: "Workout repo root.")
    var path: String = "."

    @Option(name: .long, help: "Output bundle file.")
    var to: String = "plusplus-export.json"

    func run() throws {
        let bundle = try WorkoutRepo(root: URL(fileURLWithPath: path)).loadBundle()
        try requireValid(bundle)
        try InterchangeCodec.encode(bundle).write(to: URL(fileURLWithPath: to))
        print("Wrote \(to) — \(bundle.exercises.count) exercises, \(bundle.workouts.count) workouts, \(bundle.sessions.count) sessions")
    }
}

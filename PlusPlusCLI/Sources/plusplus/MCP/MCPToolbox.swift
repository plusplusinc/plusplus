import Foundation
import PlusPlusKit

/// The tools `plusplus mcp` exposes, over the same internals as the CLI
/// commands: read tools return the interchange DTOs / JSON reports
/// verbatim, and the one mutating tool writes a git branch — never main,
/// never a push (transport and auth stay git's job, per the CLI design).
enum MCPToolbox {
    struct ToolError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Definitions (tools/list)

    static var definitions: [[String: Any]] { [
        [
            "name": "list_exercises",
            "description": "All exercises in the workout repo (interchange schema): name, muscle group, type, equipment, notes, video.",
            "inputSchema": emptySchema,
        ],
        [
            "name": "list_workouts",
            "description": "All workout templates: groups (a group with >1 exercise is a superset), sets, targets (weight/reps/rep-ranges/duration), rest.",
            "inputSchema": emptySchema,
        ],
        [
            "name": "get_history",
            "description": "Finished training sessions, newest first. Every set carries targets and actuals.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Max sessions to return (default 20)."],
                    "workout": ["type": "string", "description": "Only sessions of this workout (case-insensitive)."],
                ],
            ],
        ],
        [
            "name": "stats",
            "description": "Per-exercise aggregates over completed sets: sessions, sets, total reps, best weight/duration, last performed.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "exercise": ["type": "string", "description": "Only this exercise (case-insensitive)."],
                ],
            ],
        ],
        [
            "name": "lint",
            "description": "Validate the repo against the interchange schema. Returns {valid, counts, issues}.",
            "inputSchema": emptySchema,
        ],
        [
            "name": "propose_program_change",
            "description": "Write program-file changes to a NEW git branch and commit them — never to the current branch, never pushed. Returns the branch name; pushing and opening a PR is the caller's job. Paths must be under program/ (history is append-only and off limits). The repo must have a clean work tree. Changes that fail lint are rolled back and rejected.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "Commit message describing the change."],
                    "branch": ["type": "string", "description": "Branch name (default: plusplus/proposal-<timestamp>)."],
                    "files": [
                        "type": "array",
                        "description": "Files to create or overwrite.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "path": ["type": "string", "description": "Repo-relative path under program/."],
                                "content": ["type": "string", "description": "Full file content (interchange JSON)."],
                            ],
                            "required": ["path", "content"],
                        ],
                    ],
                ],
                "required": ["message", "files"],
            ],
        ],
    ] }

    private static var emptySchema: [String: Any] { ["type": "object", "properties": [String: Any]()] }

    // MARK: - Dispatch (tools/call)

    static func call(name: String, arguments: [String: Any], repoRoot: String) throws -> String {
        switch name {
        case "list_exercises":
            let bundle = try BundleSource.load(path: repoRoot)
            return try encode(bundle.exercises)
        case "list_workouts":
            let bundle = try BundleSource.load(path: repoRoot)
            return try encode(bundle.workouts)
        case "get_history":
            let bundle = try BundleSource.load(path: repoRoot)
            var sessions = bundle.sessions.sorted { $0.startedAt > $1.startedAt }
            if let workout = arguments["workout"] as? String {
                sessions = sessions.filter { $0.workoutName.lowercased() == workout.lowercased() }
            }
            let limit = arguments["limit"] as? Int ?? 20
            return try encode(Array(sessions.prefix(max(0, limit))))
        case "stats":
            let bundle = try BundleSource.load(path: repoRoot)
            var stats = HistoryStats.compute(from: bundle.sessions)
            if let exercise = arguments["exercise"] as? String {
                stats = stats.filter { $0.name.lowercased() == exercise.lowercased() }
            }
            return try encode(StatsReport(stats: stats))
        case "lint":
            let bundle = try BundleSource.load(path: repoRoot)
            return try encode(LintReport(bundle: bundle, issues: InterchangeValidator.validate(bundle)))
        case "propose_program_change":
            return try proposeProgramChange(arguments: arguments, repoRoot: repoRoot)
        default:
            throw ToolError(description: "unknown tool: \(name)")
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try InterchangeCodec.encode(value), as: UTF8.self)
    }

    // MARK: - propose_program_change

    static func proposeProgramChange(arguments: [String: Any], repoRoot: String) throws -> String {
        guard let message = arguments["message"] as? String, !message.isEmpty else {
            throw ToolError(description: "message is required")
        }
        guard let rawFiles = arguments["files"] as? [[String: Any]], !rawFiles.isEmpty else {
            throw ToolError(description: "files is required and must be non-empty")
        }

        var files: [(path: String, content: String)] = []
        for raw in rawFiles {
            guard let path = raw["path"] as? String, let content = raw["content"] as? String else {
                throw ToolError(description: "each file needs path and content")
            }
            guard isAllowedProgramPath(path) else {
                throw ToolError(description: "refusing to write \(path): only program/**.json is writable (history is append-only)")
            }
            files.append((path, content))
        }

        guard try Git.run(["status", "--porcelain"], in: repoRoot).isEmpty else {
            throw ToolError(description: "work tree is not clean — commit or stash first")
        }
        let originalBranch = try Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repoRoot)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
        let branch = (arguments["branch"] as? String) ?? "plusplus/proposal-\(stamp)"

        try Git.run(["checkout", "-b", branch], in: repoRoot)
        do {
            let root = URL(fileURLWithPath: repoRoot)
            for file in files {
                let target = root.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data(file.content.utf8).write(to: target)
            }

            // The proposal must lint clean or it doesn't get a branch.
            let bundle = try BundleSource.load(path: repoRoot)
            let issues = InterchangeValidator.validate(bundle)
            guard issues.isEmpty else {
                throw ToolError(description: "proposal fails lint: " + issues.map(\.description).joined(separator: "; "))
            }

            try Git.run(["add", "-A"], in: repoRoot)
            try Git.run(["commit", "-m", message], in: repoRoot)
            let sha = try Git.run(["rev-parse", "--short", "HEAD"], in: repoRoot)
            try Git.run(["checkout", originalBranch], in: repoRoot)

            return try encode(ProposalReceipt(
                branch: branch,
                commit: sha,
                files: files.map(\.path),
                note: "Committed locally, not pushed. Review with `git show \(branch)`, then `git push -u origin \(branch)` and open a PR."
            ))
        } catch {
            // Roll back: discard the partial write and the branch.
            _ = try? Git.run(["checkout", "--", "."], in: repoRoot)
            _ = try? Git.run(["clean", "-fd", "program"], in: repoRoot)
            _ = try? Git.run(["checkout", originalBranch], in: repoRoot)
            _ = try? Git.run(["branch", "-D", branch], in: repoRoot)
            throw error
        }
    }

    struct ProposalReceipt: Codable {
        let branch: String
        let commit: String
        let files: [String]
        let note: String
    }

    /// program/**.json only — no traversal, no absolute paths, no history.
    static func isAllowedProgramPath(_ path: String) -> Bool {
        guard path.hasSuffix(".json"), !path.hasPrefix("/") else { return false }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.first == "program", parts.count >= 2 else { return false }
        return !parts.contains("..") && !parts.contains(".")
    }
}

/// Thin git runner — the CLI's one transport (see the decisions log:
/// git is transport and auth; this tool never talks to GitHub).
enum Git {
    struct GitError: Error, CustomStringConvertible {
        let command: String
        let output: String
        var description: String { "git \(command) failed: \(output)" }
    }

    @discardableResult
    static func run(_ args: [String], in root: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root] + args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitError(command: args.joined(separator: " "), output: stderr.isEmpty ? stdout : stderr)
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

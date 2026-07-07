import Foundation
import Testing
import PlusPlusKit
@testable import plusplus

@Suite("MCP server")
struct MCPServerTests {
    // MARK: - Fixtures

    /// A scaffolded example repo (optionally a git repo with an initial commit).
    private func makeRepo(git: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plusplus-mcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in try InitCommand.scaffoldFiles(example: true) {
            let target = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try file.data.write(to: target)
        }
        if git {
            try Git.run(["init", "-b", "main"], in: root.path)
            try Git.run(["config", "user.email", "test@example.com"], in: root.path)
            try Git.run(["config", "user.name", "Test"], in: root.path)
            try Git.run(["add", "-A"], in: root.path)
            try Git.run(["commit", "-m", "Initial"], in: root.path)
        }
        return root
    }

    private func request(_ id: Int, _ method: String, params: [String: Any] = [:]) -> String {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    private func decode(_ response: String?) throws -> [String: Any] {
        let text = try #require(response)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    private func toolText(_ response: String?) throws -> String {
        let message = try decode(response)
        let result = try #require(message["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        return try #require(content.first?["text"] as? String)
    }

    // MARK: - Protocol

    @Test("initialize advertises the tools capability")
    func initialize() throws {
        let server = MCPServer(repoRoot: ".")
        let message = try decode(server.handle(line: request(1, "initialize")))
        let result = try #require(message["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == MCPServer.protocolVersion)
        let info = try #require(result["serverInfo"] as? [String: Any])
        #expect(info["name"] as? String == "plusplus")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
    }

    @Test("Notifications get no response; unknown methods get -32601")
    func protocolEdges() throws {
        let server = MCPServer(repoRoot: ".")
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)

        let message = try decode(server.handle(line: request(2, "nope/nothing")))
        let error = try #require(message["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)

        let garbage = try decode(server.handle(line: "not json at all"))
        #expect((garbage["error"] as? [String: Any])?["code"] as? Int == -32700)
    }

    @Test("tools/list names the whole toolbox")
    func toolsList() throws {
        let server = MCPServer(repoRoot: ".")
        let message = try decode(server.handle(line: request(3, "tools/list")))
        let result = try #require(message["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == ["list_exercises", "list_routines", "get_history", "stats", "lint", "propose_program_change"])
        #expect(tools.allSatisfy { $0["inputSchema"] != nil && $0["description"] != nil })
    }

    // MARK: - Read tools

    @Test("lint and list tools serve the example repo")
    func readTools() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = MCPServer(repoRoot: root.path)

        let lintText = try toolText(server.handle(line: request(4, "tools/call", params: ["name": "lint"])))
        let lint = try InterchangeCodec.decoder().decode(LintReport.self, from: Data(lintText.utf8))
        #expect(lint.valid)
        #expect(lint.counts.exercises == 1 && lint.counts.routines == 1)

        let routinesText = try toolText(server.handle(line: request(5, "tools/call", params: ["name": "list_routines"])))
        let routines = try InterchangeCodec.decoder().decode([RoutineDTO].self, from: Data(routinesText.utf8))
        #expect(routines.map(\.name) == ["Example Day"])

        let exercisesText = try toolText(server.handle(line: request(6, "tools/call", params: ["name": "list_exercises"])))
        let exercises = try InterchangeCodec.decoder().decode([ExerciseDTO].self, from: Data(exercisesText.utf8))
        #expect(exercises.map(\.name) == ["Push-Up"])
    }

    @Test("Unknown tools surface as tool errors, not protocol errors")
    func unknownTool() throws {
        let server = MCPServer(repoRoot: ".")
        let message = try decode(server.handle(line: request(7, "tools/call", params: ["name": "bogus"])))
        let result = try #require(message["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
    }

    // MARK: - propose_program_change

    @Test("A valid proposal lands on a new branch and leaves the work tree clean")
    func proposal() throws {
        let root = try makeRepo(git: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = MCPServer(repoRoot: root.path)

        let routine = RoutineDTO(name: "Example Day", restSeconds: 60, groups: [
            .init(sets: 4, exercises: [.init(exercise: "Push-Up", reps: 12)])
        ])
        let content = String(decoding: try InterchangeCodec.encode(RoutineDocument(routine: routine)), as: UTF8.self)

        let text = try toolText(server.handle(line: request(8, "tools/call", params: [
            "name": "propose_program_change",
            "arguments": [
                "message": "Bump Example Day to 4x12",
                "branch": "plusplus/test-proposal",
                "files": [["path": "program/routines/example-day.json", "content": content]],
            ],
        ])))
        let receipt = try InterchangeCodec.decoder().decode(MCPToolbox.ProposalReceipt.self, from: Data(text.utf8))
        #expect(receipt.branch == "plusplus/test-proposal")

        // Back on main, tree clean, and the branch carries the commit.
        #expect(try Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root.path) == "main")
        #expect(try Git.run(["status", "--porcelain"], in: root.path).isEmpty)
        let subject = try Git.run(["log", "-1", "--format=%s", "plusplus/test-proposal"], in: root.path)
        #expect(subject == "Bump Example Day to 4x12")
    }

    @Test("A proposal that fails lint is rolled back completely")
    func proposalRollsBack() throws {
        let root = try makeRepo(git: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = MCPServer(repoRoot: root.path)

        let message = try decode(server.handle(line: request(9, "tools/call", params: [
            "name": "propose_program_change",
            "arguments": [
                "message": "Bad rest",
                "files": [["path": "program/routines/bad.json", "content": #"{"schemaVersion":1,"routine":{"name":"Bad","restSeconds":2,"groups":[]}}"#]],
            ],
        ])))
        let result = try #require(message["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)

        #expect(try Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root.path) == "main")
        #expect(try Git.run(["status", "--porcelain"], in: root.path).isEmpty)
        let branches = try Git.run(["branch", "--list", "plusplus/*"], in: root.path)
        #expect(branches.isEmpty, "Failed proposals must not leave branches behind")
    }

    @Test("History paths and traversal are refused")
    func pathPolicy() {
        #expect(MCPToolbox.isAllowedProgramPath("program/routines/push-day.json"))
        #expect(MCPToolbox.isAllowedProgramPath("program/exercises/band-pulses.json"))
        #expect(!MCPToolbox.isAllowedProgramPath("history/2026/2026-07-06-push-day.json"))
        #expect(!MCPToolbox.isAllowedProgramPath("program/../history/x.json"))
        #expect(!MCPToolbox.isAllowedProgramPath("/etc/passwd.json"))
        #expect(!MCPToolbox.isAllowedProgramPath("program/routines/evil.sh"))
        #expect(!MCPToolbox.isAllowedProgramPath("README.md"))
    }
}

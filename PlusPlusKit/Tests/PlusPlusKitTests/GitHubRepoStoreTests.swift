import Foundation
import Testing
import PlusPlusKit

@Suite("GitHubRepoStore")
struct GitHubRepoStoreTests {
    private let coordinate = GitHubRepoCoordinate(owner: "octocat", repo: "workouts", branch: "main")

    private func store(_ client: ScriptedHTTPClient, token: String? = "gho_token") -> GitHubRepoStore {
        GitHubRepoStore(coordinate: coordinate, tokens: InMemoryTokenStore(token: token), client: client)
    }

    // MARK: - fetchAll

    @Test("fetchAll reads synced files and decodes base64 blobs")
    func fetchAllReadsSyncedFiles() async throws {
        let routineData = Data("{\"routine\":true}".utf8)
        let client = ScriptedHTTPClient { request, _ in
            if request.path.contains("git/trees") {
                return GHResponse.json(["tree": [
                    ["path": "program/routines/push-day.json", "type": "blob", "sha": "sha-routine"],
                    ["path": "history/2026/2026-07-05-push-day.json", "type": "blob", "sha": "sha-session"],
                    // Not synced: the user's own repo files stay untouched.
                    ["path": "README.md", "type": "blob", "sha": "sha-readme"],
                    ["path": "program/routines", "type": "tree", "sha": "sha-dir"],
                ]])
            }
            if request.path.contains("git/blobs/sha-routine") {
                return GHResponse.json(["content": routineData.base64EncodedString(), "encoding": "base64"])
            }
            if request.path.contains("git/blobs/sha-session") {
                return GHResponse.json(["content": Data("{}".utf8).base64EncodedString(), "encoding": "base64"])
            }
            return GHResponse.status(500, body: "unexpected \(request.path)")
        }

        let files = try await store(client).fetchAll()

        #expect(files.count == 2)
        #expect(files["program/routines/push-day.json"] == routineData)
        #expect(files["history/2026/2026-07-05-push-day.json"] == Data("{}".utf8))
        #expect(files["README.md"] == nil, "Non-interchange files must never be fetched")
    }

    @Test("fetchAll on an empty repo (no tree) returns nothing")
    func fetchAllEmptyRepo() async throws {
        let client = ScriptedHTTPClient { request, _ in
            request.path.contains("git/trees") ? GHResponse.status(409, body: "empty") : GHResponse.status(500)
        }
        let files = try await store(client).fetchAll()
        #expect(files.isEmpty)
    }

    @Test("fetchAll without a token throws notAuthenticated")
    func fetchAllUnauthenticated() async throws {
        let client = ScriptedHTTPClient { _, _ in GHResponse.status(200) }
        await #expect(throws: GitHubRepoStore.StoreError.notAuthenticated) {
            try await store(client, token: nil).fetchAll()
        }
        #expect(client.requests.isEmpty)
    }

    // MARK: - write (git-data commit)

    @Test("write commits all files in one commit atop the branch head")
    func writeCommitsBatch() async throws {
        let client = ScriptedHTTPClient { request, _ in
            switch (request.method, request.path) {
            case (.get, let p) where p.contains("git/ref/heads/main"):
                return GHResponse.json(["object": ["sha": "head-commit"]])
            case (.get, let p) where p.contains("git/commits/head-commit"):
                return GHResponse.json(["tree": ["sha": "head-tree"]])
            case (.post, let p) where p.contains("git/blobs"):
                return GHResponse.json(["sha": "blob-\(request.jsonBody?["content"] as? String ?? "")"], status: 201)
            case (.post, let p) where p.contains("git/trees"):
                return GHResponse.json(["sha": "new-tree"], status: 201)
            case (.post, let p) where p.contains("git/commits"):
                return GHResponse.json(["sha": "new-commit"], status: 201)
            case (.patch, let p) where p.contains("git/refs/heads/main"):
                return GHResponse.json(["object": ["sha": "new-commit"]])
            default:
                return GHResponse.status(500, body: "unexpected \(request.method.rawValue) \(request.path)")
            }
        }

        try await store(client).write([
            FileWrite(path: "program/routines/push-day.json", data: Data("A".utf8)),
            FileWrite(path: "program/exercises/squat.json", data: Data("B".utf8)),
        ], message: "Sync: push-day, squat")

        // Two blobs, a tree layered on the head tree, a commit parented on the
        // head commit, and a fast-forward ref update.
        let trees = client.requests.filter { $0.path.contains("git/trees") && $0.method == .post }
        #expect(trees.count == 1)
        #expect(trees.first?.jsonBody?["base_tree"] as? String == "head-tree")
        let treeEntries = trees.first?.jsonBody?["tree"] as? [[String: Any]]
        #expect(treeEntries?.count == 2)

        let commits = client.requests.filter { $0.path.hasSuffix("git/commits") && $0.method == .post }
        #expect(commits.first?.jsonBody?["message"] as? String == "Sync: push-day, squat")
        #expect(commits.first?.jsonBody?["parents"] as? [String] == ["head-commit"])

        let refUpdate = client.requests.first { $0.method == .patch }
        #expect(refUpdate?.jsonBody?["sha"] as? String == "new-commit")
        #expect(refUpdate?.jsonBody?["force"] as? Bool == false, "The ref update must not force — that's the concurrency guard")
    }

    @Test("A non-fast-forward ref update surfaces as a conflict")
    func writeConflict() async throws {
        let client = ScriptedHTTPClient { request, _ in
            switch (request.method, request.path) {
            case (.get, let p) where p.contains("git/ref/heads/main"):
                return GHResponse.json(["object": ["sha": "head-commit"]])
            case (.get, let p) where p.contains("git/commits/head-commit"):
                return GHResponse.json(["tree": ["sha": "head-tree"]])
            case (.post, let p) where p.contains("git/blobs"):
                return GHResponse.json(["sha": "blob"], status: 201)
            case (.post, let p) where p.contains("git/trees"):
                return GHResponse.json(["sha": "new-tree"], status: 201)
            case (.post, let p) where p.contains("git/commits"):
                return GHResponse.json(["sha": "new-commit"], status: 201)
            case (.patch, _):
                // Another device pushed between our fetch and this update.
                return GHResponse.status(422, body: "Update is not a fast forward")
            default:
                return GHResponse.status(500)
            }
        }
        await #expect(throws: GitHubRepoStore.StoreError.conflict) {
            try await store(client).write([FileWrite(path: "program/x.json", data: Data("A".utf8))], message: "Sync: x")
        }
    }

    @Test("write into an empty repo creates the branch ref")
    func writeInitialCommit() async throws {
        let client = ScriptedHTTPClient { request, _ in
            switch (request.method, request.path) {
            case (.get, let p) where p.contains("git/ref/heads/main"):
                return GHResponse.status(404, body: "no ref yet")
            case (.post, let p) where p.contains("git/blobs"):
                return GHResponse.json(["sha": "blob"], status: 201)
            case (.post, let p) where p.contains("git/trees"):
                return GHResponse.json(["sha": "new-tree"], status: 201)
            case (.post, let p) where p.contains("git/commits"):
                return GHResponse.json(["sha": "new-commit"], status: 201)
            case (.post, let p) where p.hasSuffix("git/refs"):
                return GHResponse.json(["ref": "refs/heads/main"], status: 201)
            default:
                return GHResponse.status(500, body: "unexpected \(request.method.rawValue) \(request.path)")
            }
        }

        try await store(client).write([FileWrite(path: "program/x.json", data: Data("A".utf8))], message: "Sync: x")

        // No base_tree (nothing to layer on), no parents, and a ref CREATE.
        let tree = client.requests.first { $0.path.contains("git/trees") && $0.method == .post }
        #expect(tree?.jsonBody?["base_tree"] == nil)
        let commit = client.requests.first { $0.path.hasSuffix("git/commits") && $0.method == .post }
        #expect((commit?.jsonBody?["parents"] as? [String])?.isEmpty == true)
        let refCreate = client.requests.first { $0.path.hasSuffix("git/refs") && $0.method == .post }
        #expect(refCreate?.jsonBody?["ref"] as? String == "refs/heads/main")
    }

    @Test("Writing no files is a no-op with no network calls")
    func writeEmptyIsNoOp() async throws {
        let client = ScriptedHTTPClient { _, _ in GHResponse.status(500) }
        try await store(client).write([], message: "nothing")
        #expect(client.requests.isEmpty)
    }
}

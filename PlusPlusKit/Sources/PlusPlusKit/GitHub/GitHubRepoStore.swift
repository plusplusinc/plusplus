import Foundation

/// The GitHub implementation of `RepoStore` — the app's real sync transport.
/// Reads every interchange file with the Git Trees + Blobs API and applies a
/// batch of writes as ONE commit with the Git Data API (blobs → tree →
/// commit → ref), so a sync pass is a single reviewable commit, not one per
/// file. The ref update is the optimistic-concurrency guard: a non-fast-forward
/// (another device pushed first) surfaces as `.conflict`, and the caller
/// refetches and replans.
///
/// The app never runs git on iOS (docs/PLATFORM.md) — this is the whole
/// "no git" story. Pure over `HTTPClient` + `TokenStore`, so it's fully
/// exercised on Linux against a scripted fake.
public struct GitHubRepoStore: RepoStore {
    private let coordinate: GitHubRepoCoordinate
    private let tokens: any TokenStore
    private let client: any HTTPClient
    private let apiHost: URL
    /// Optional content-addressed blob cache — a hit skips the per-blob GET
    /// entirely (SHAs are content-addressed, so a hit can never be stale).
    private let blobCache: (any GitBlobCache)?

    /// Only files under these prefixes participate in sync — the interchange
    /// layout (`program/…` templates + `history/…` sessions). A user's README,
    /// CLAUDE.md, or skills at the repo root are theirs and are never fetched,
    /// planned against, or overwritten.
    static let syncedPrefixes = ["program/", "\(FileLayout.historyDirectory)/"]

    public init(
        coordinate: GitHubRepoCoordinate,
        tokens: any TokenStore,
        client: any HTTPClient,
        apiHost: URL = URL(string: "https://api.github.com")!,
        blobCache: (any GitBlobCache)? = nil
    ) {
        self.coordinate = coordinate
        self.tokens = tokens
        self.client = client
        self.apiHost = apiHost
        self.blobCache = blobCache
    }

    public enum StoreError: Error, Equatable {
        case notAuthenticated
        case notFound
        /// The branch moved under us (another device pushed) — refetch, replan.
        case conflict
        case malformedResponse
        case http(status: Int, message: String)
    }

    // MARK: - RepoStore.fetchAll

    public func fetchAll() async throws -> [String: Data] {
        let treeResponse = try await send(.get, path: "git/trees/\(coordinate.branch)", query: [("recursive", "1")])
        // An empty repo (no commits yet) has no branch tree — nothing to pull.
        if treeResponse.status == 404 || treeResponse.status == 409 { return [:] }
        try throwIfError(treeResponse)
        guard let tree = try? JSONDecoder().decode(TreeResponse.self, from: treeResponse.body) else {
            throw StoreError.malformedResponse
        }

        var files: [String: Data] = [:]
        for entry in tree.tree where entry.type == "blob" && Self.isSynced(entry.path) {
            guard let sha = entry.sha else { continue }
            if let cached = blobCache?.data(forSHA: sha) {
                files[entry.path] = cached
                continue
            }
            let data = try await fetchBlob(sha: sha)
            blobCache?.store(data, sha: sha)
            files[entry.path] = data
        }
        return files
    }

    private func fetchBlob(sha: String) async throws -> Data {
        let response = try await send(.get, path: "git/blobs/\(sha)")
        try throwIfError(response)
        guard let blob = try? JSONDecoder().decode(BlobResponse.self, from: response.body) else {
            throw StoreError.malformedResponse
        }
        // GitHub base64-encodes blob content, wrapped at 76 chars with newlines.
        let cleaned = blob.content.replacingOccurrences(of: "\n", with: "")
        guard blob.encoding == "base64", let data = Data(base64Encoded: cleaned) else {
            throw StoreError.malformedResponse
        }
        return data
    }

    // MARK: - RepoStore.write (one commit via the Git Data API)

    public func write(_ files: [FileWrite], message: String) async throws {
        guard !files.isEmpty else { return }

        // 1. Current branch head (parent commit + its tree), if the branch exists.
        var head = try await currentHead()
        if head == nil {
            // An UNBORN repo (the user created it empty and installed the App
            // on it — the app's own bootstrap uses auto_init, but a
            // brought-your-own repo skips that). GitHub's Git Data API can't
            // create the first commit on a repo with zero commits (blobs /
            // trees / refs all 409 "Git Repository is empty"), so birth the
            // branch via the Contents API — which CAN — then build on it.
            try await seedInitialCommit()
            head = try await currentHead()
        }

        // 2. A blob per file. Warm the cache with what we just pushed — the
        // next fetchAll will list these SHAs, and we already hold the bytes.
        var treeEntries: [TreeEntryInput] = []
        for file in files {
            let sha = try await createBlob(file.data)
            blobCache?.store(file.data, sha: sha)
            treeEntries.append(TreeEntryInput(path: file.path, mode: "100644", type: "blob", sha: sha))
        }

        // 3. A tree layered on the parent's tree (base_tree preserves untouched files).
        let newTree = try await createTree(base: head?.treeSHA, entries: treeEntries)

        // 4. The commit.
        let newCommit = try await createCommit(message: message, tree: newTree, parents: head.map { [$0.commitSHA] } ?? [])

        // 5. Advance the ref. force:false is the concurrency guard.
        try await updateOrCreateRef(to: newCommit, hadHead: head != nil)
    }

    // MARK: - Git Data primitives

    private struct Head { let commitSHA: String; let treeSHA: String }

    private func currentHead() async throws -> Head? {
        let refResponse = try await send(.get, path: "git/ref/heads/\(coordinate.branch)")
        if refResponse.status == 404 || refResponse.status == 409 { return nil }
        try throwIfError(refResponse)
        guard let ref = try? JSONDecoder().decode(RefResponse.self, from: refResponse.body) else {
            throw StoreError.malformedResponse
        }
        let commitResponse = try await send(.get, path: "git/commits/\(ref.object.sha)")
        try throwIfError(commitResponse)
        guard let commit = try? JSONDecoder().decode(CommitResponse.self, from: commitResponse.body) else {
            throw StoreError.malformedResponse
        }
        return Head(commitSHA: ref.object.sha, treeSHA: commit.tree.sha)
    }

    /// Births the default branch on an unborn repo with one commit through
    /// the Contents API (the only write endpoint that works with zero
    /// commits). Mirrors the `auto_init` the bootstrap uses when the app
    /// creates the repo itself. The README lives at the repo root, outside
    /// the synced prefixes, so sync never reads or overwrites it. It carries a
    /// PlusPlus link so a public sync repo is a discovery surface (Dave).
    private func seedInitialCommit() async throws {
        let readme = Data(
            "# PlusPlus data\n\nWorkout program and history, synced from [PlusPlus](https://plusplus.fit), the hackable workout tracker for incrementing yourself.\n".utf8
        )
        let body = try JSONEncoder().encode(ContentsPutInput(
            message: "Initialize repository",
            content: readme.base64EncodedString(),
            branch: coordinate.branch
        ))
        let response = try await send(.put, path: "contents/README.md", jsonBody: body)
        try throwIfError(response)
    }

    private func createBlob(_ data: Data) async throws -> String {
        let body = try JSONEncoder().encode(BlobInput(content: data.base64EncodedString(), encoding: "base64"))
        let response = try await send(.post, path: "git/blobs", jsonBody: body)
        try throwIfError(response)
        return try shaOf(response)
    }

    private func createTree(base: String?, entries: [TreeEntryInput]) async throws -> String {
        let body = try JSONEncoder().encode(TreeInput(base_tree: base, tree: entries))
        let response = try await send(.post, path: "git/trees", jsonBody: body)
        try throwIfError(response)
        return try shaOf(response)
    }

    private func createCommit(message: String, tree: String, parents: [String]) async throws -> String {
        let body = try JSONEncoder().encode(CommitInput(message: message, tree: tree, parents: parents))
        let response = try await send(.post, path: "git/commits", jsonBody: body)
        try throwIfError(response)
        return try shaOf(response)
    }

    private func updateOrCreateRef(to commitSHA: String, hadHead: Bool) async throws {
        if hadHead {
            let body = try JSONEncoder().encode(RefUpdateInput(sha: commitSHA, force: false))
            let response = try await send(.patch, path: "git/refs/heads/\(coordinate.branch)", jsonBody: body)
            // 422 on a ref update is a non-fast-forward: someone pushed first.
            if response.status == 422 { throw StoreError.conflict }
            try throwIfError(response)
        } else {
            let body = try JSONEncoder().encode(RefCreateInput(ref: "refs/heads/\(coordinate.branch)", sha: commitSHA))
            let response = try await send(.post, path: "git/refs", jsonBody: body)
            try throwIfError(response)
        }
    }

    // MARK: - Transport

    private func send(
        _ method: HTTPRequest.Method,
        path: String,
        query: [(String, String)] = [],
        jsonBody: Data? = nil
    ) async throws -> HTTPResponse {
        guard let token = try tokens.load(), !token.isEmpty else {
            throw StoreError.notAuthenticated
        }
        var components = URLComponents(
            url: apiHost.appendingPathComponent("repos/\(coordinate.owner)/\(coordinate.repo)/\(path)"),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components?.url else { throw StoreError.malformedResponse }

        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        if jsonBody != nil { headers["Content-Type"] = "application/json" }
        return try await client.send(HTTPRequest(method: method, url: url, headers: headers, body: jsonBody))
    }

    private func throwIfError(_ response: HTTPResponse) throws {
        guard !response.isSuccess else { return }
        switch response.status {
        case 401: throw StoreError.notAuthenticated
        case 404: throw StoreError.notFound
        case 409: throw StoreError.conflict
        default:
            let message = String(data: response.body, encoding: .utf8) ?? ""
            throw StoreError.http(status: response.status, message: message)
        }
    }

    private func shaOf(_ response: HTTPResponse) throws -> String {
        guard let object = try? JSONDecoder().decode(SHAOnly.self, from: response.body) else {
            throw StoreError.malformedResponse
        }
        return object.sha
    }

    static func isSynced(_ path: String) -> Bool {
        syncedPrefixes.contains { path.hasPrefix($0) }
    }

    // MARK: - Wire shapes

    private struct TreeResponse: Decodable { let tree: [Entry]
        struct Entry: Decodable { let path: String; let type: String; let sha: String? }
    }
    private struct BlobResponse: Decodable { let content: String; let encoding: String }
    private struct RefResponse: Decodable { let object: Object; struct Object: Decodable { let sha: String } }
    private struct CommitResponse: Decodable { let tree: Tree; struct Tree: Decodable { let sha: String } }
    private struct SHAOnly: Decodable { let sha: String }

    private struct BlobInput: Encodable { let content: String; let encoding: String }
    private struct TreeEntryInput: Encodable { let path: String; let mode: String; let type: String; let sha: String }
    private struct TreeInput: Encodable { let base_tree: String?; let tree: [TreeEntryInput] }
    private struct CommitInput: Encodable { let message: String; let tree: String; let parents: [String] }
    private struct RefUpdateInput: Encodable { let sha: String; let force: Bool }
    private struct RefCreateInput: Encodable { let ref: String; let sha: String }
    private struct ContentsPutInput: Encodable { let message: String; let content: String; let branch: String }
}

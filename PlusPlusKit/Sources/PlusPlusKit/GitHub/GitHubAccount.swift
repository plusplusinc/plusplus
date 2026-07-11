import Foundation

/// The account-level GitHub calls repo bootstrap needs, separate from the
/// per-repo `GitHubRepoStore`: who am I, does my routine repo exist yet, and
/// create it (private) if not. The app calls these once when connecting, then
/// builds a `GitHubRepoStore` on the resulting coordinate.
///
/// Pure over `HTTPClient` + `TokenStore` — Linux-tested against a fake.
public struct GitHubAccount: Sendable {
    private let tokens: any TokenStore
    private let client: any HTTPClient
    private let apiHost: URL

    public init(
        tokens: any TokenStore,
        client: any HTTPClient,
        apiHost: URL = URL(string: "https://api.github.com")!
    ) {
        self.tokens = tokens
        self.client = client
        self.apiHost = apiHost
    }

    public enum AccountError: Error, Equatable {
        case notAuthenticated
        case malformedResponse
        case http(status: Int, message: String)
    }

    /// The authenticated user's login — the `owner` half of a coordinate.
    public func currentLogin() async throws -> String {
        let response = try await send(.get, path: "user")
        try throwIfError(response)
        guard let user = try? JSONDecoder().decode(User.self, from: response.body) else {
            throw AccountError.malformedResponse
        }
        return user.login
    }

    /// Whether `owner/name` already exists (a returning user's repo).
    public func repositoryExists(owner: String, name: String) async throws -> Bool {
        let response = try await send(.get, path: "repos/\(owner)/\(name)")
        if response.status == 404 { return false }
        try throwIfError(response)
        return true
    }

    /// The coordinate for `owner/name` — carrying its REAL default branch — if
    /// it exists, else nil. Bootstrap adopts an existing repo through this so
    /// sync targets the branch the repo actually uses (a repo defaulting to
    /// `master`/`trunk` must not be synced against a hardcoded `main`).
    public func repository(owner: String, name: String) async throws -> GitHubRepoCoordinate? {
        let response = try await send(.get, path: "repos/\(owner)/\(name)")
        if response.status == 404 { return nil }
        try throwIfError(response)
        guard let repo = try? JSONDecoder().decode(Repository.self, from: response.body) else {
            throw AccountError.malformedResponse
        }
        return GitHubRepoCoordinate(
            owner: repo.owner.login,
            repo: repo.name,
            branch: repo.default_branch ?? "main"
        )
    }

    /// Creates a PRIVATE repo on the authenticated user's account, auto-init'd
    /// so it has a default branch (and thus a ref for the first sync to
    /// fast-forward). Returns the coordinate to sync against.
    @discardableResult
    public func createRoutineRepository(
        name: String,
        description: String = "My PlusPlus routines and history."
    ) async throws -> GitHubRepoCoordinate {
        let body = try JSONEncoder().encode(CreateRepoInput(
            name: name, description: description, isPrivate: true, autoInit: true
        ))
        let response = try await send(.post, path: "user/repos", jsonBody: body)
        try throwIfError(response)
        guard let repo = try? JSONDecoder().decode(Repository.self, from: response.body) else {
            throw AccountError.malformedResponse
        }
        return GitHubRepoCoordinate(
            owner: repo.owner.login,
            repo: repo.name,
            branch: repo.default_branch ?? "main"
        )
    }

    // MARK: - Transport

    private func send(_ method: HTTPRequest.Method, path: String, jsonBody: Data? = nil) async throws -> HTTPResponse {
        guard let token = try tokens.load(), !token.isEmpty else {
            throw AccountError.notAuthenticated
        }
        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        if jsonBody != nil { headers["Content-Type"] = "application/json" }
        return try await client.send(HTTPRequest(
            method: method,
            url: apiHost.appendingPathComponent(path),
            headers: headers,
            body: jsonBody
        ))
    }

    private func throwIfError(_ response: HTTPResponse) throws {
        guard !response.isSuccess else { return }
        if response.status == 401 { throw AccountError.notAuthenticated }
        let message = String(data: response.body, encoding: .utf8) ?? ""
        throw AccountError.http(status: response.status, message: message)
    }

    // MARK: - Wire shapes

    private struct User: Decodable { let login: String }
    private struct Repository: Decodable { let name: String; let owner: Owner; let default_branch: String?
        struct Owner: Decodable { let login: String }
    }
    private struct CreateRepoInput: Encodable {
        let name: String; let description: String; let isPrivate: Bool; let autoInit: Bool
        enum CodingKeys: String, CodingKey {
            case name, description
            case isPrivate = "private"
            case autoInit = "auto_init"
        }
    }
}

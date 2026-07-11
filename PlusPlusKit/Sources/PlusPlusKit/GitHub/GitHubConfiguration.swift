import Foundation

/// The GitHub App identity the device flow authenticates against. The client
/// ID is NOT a secret (it ships in the binary; device flow needs no client
/// secret) — but it doesn't exist until the owner registers the App
/// (docs/PLATFORM.md TODO, issue #23). So it's configuration, injected at the
/// edge, never hardcoded here: the app reads it from Info.plist and constructs
/// this. Kit ships no default.
public struct GitHubAppConfiguration: Sendable, Equatable {
    public let clientID: String

    public init(clientID: String) {
        self.clientID = clientID
    }
}

/// Which repo on which account a `GitHubRepoStore` targets, plus the branch it
/// commits to. The store never guesses these — bootstrap (Mac session) picks
/// the repo and hands them in.
public struct GitHubRepoCoordinate: Sendable, Equatable {
    public let owner: String
    public let repo: String
    public let branch: String

    public init(owner: String, repo: String, branch: String = "main") {
        self.owner = owner
        self.repo = repo
        self.branch = branch
    }
}

/// Where the access token lives. The app implements this over the Keychain
/// (Mac session); tests use `InMemoryTokenStore`. Kept synchronous — Keychain
/// access is synchronous and callers already hop threads for the network.
public protocol TokenStore: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// A process-lifetime token holder for tests and previews. Never persists —
/// the Keychain-backed store is the real thing.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func load() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func save(_ token: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.token = token
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        token = nil
    }
}

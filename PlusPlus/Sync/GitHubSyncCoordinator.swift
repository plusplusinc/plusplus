import Foundation
import SwiftData
import PlusPlusKit

/// Orchestrates GitHub sync for the app: device-flow connect, repo bootstrap,
/// and the foreground sync pass. Everything transport/auth-shaped lives in
/// PlusPlusKit (Linux-tested); this is the thin app-side glue that wires the
/// Kit adapters to the Keychain, the on-device base snapshot, and SwiftData.
///
/// One coordinator is created at app root and shared. `@MainActor` because it
/// drives UI state and touches the main `ModelContext`; the network calls
/// suspend, so the main thread isn't blocked.
///
/// Two orthogonal pieces of state, deliberately separate: **connection** is the
/// durable identity (do we hold a token + a repo?), **activity** is the
/// transient of-the-moment (authorizing / syncing / last error). A failed
/// *sync* must NOT read as disconnected — the token is still good — so it only
/// sets an `activity` error and auto-sync keeps working.
@Observable @MainActor
final class GitHubSyncCoordinator {
    /// One instance app-wide (the connect screen, Settings, and the app-root
    /// foreground sync all address the same object). Its durable state is in
    /// the Keychain + UserDefaults, so a fresh instance would agree anyway;
    /// sharing keeps the transient authorizing/syncing status coherent.
    static let shared = GitHubSyncCoordinator()

    enum Connection: Equatable {
        /// No client ID compiled in — the GitHub App isn't registered yet.
        case unconfigured
        case disconnected
        case connected
    }

    enum Activity: Equatable {
        case idle
        /// Device flow in flight: show the code, wait for approval.
        case authorizing(userCode: String, verificationURL: URL)
        case syncing
        case error(String)
    }

    private(set) var connection: Connection
    private(set) var activity: Activity = .idle
    private(set) var coordinate: GitHubRepoCoordinate?
    private(set) var lastSyncedAt: Date?
    /// A short human line about the last pass ("Pushed 3 · pulled 1").
    private(set) var lastSyncSummary: String?

    private let config: GitHubAppConfiguration?
    private let tokens: any TokenStore
    private let client: any HTTPClient

    init(
        config: GitHubAppConfiguration? = GitHubSyncSettings.appConfiguration,
        tokens: any TokenStore = KeychainTokenStore(),
        client: any HTTPClient = URLSessionHTTPClient()
    ) {
        let savedCoordinate = GitHubSyncSettings.savedCoordinate()
        self.config = config
        self.tokens = tokens
        self.client = client
        self.coordinate = savedCoordinate
        self.lastSyncedAt = GitHubSyncSettings.lastSyncedAt

        // Use the local, not self.coordinate — `connection` (the last stored
        // property) isn't initialized yet, so touching self is illegal here.
        let hasToken = ((try? tokens.load()) ?? nil) != nil
        if config == nil {
            connection = .unconfigured
        } else if hasToken, savedCoordinate != nil {
            connection = .connected
        } else {
            connection = .disconnected
        }
    }

    var isConnected: Bool { connection == .connected }

    var isSyncing: Bool {
        if case .syncing = activity { return true }
        return false
    }

    // MARK: - Connect (device flow → bootstrap)

    /// Runs the device flow to completion, then bootstraps the repo. Long-lived
    /// (it waits for the user to approve on github.com); drive it from a Task.
    func connect() async {
        guard let config else { connection = .unconfigured; return }
        let flow = GitHubDeviceFlow(config: config, client: client)
        do {
            let verification = try await flow.requestVerification()
            let url = URL(string: verification.verificationURI) ?? URL(string: "https://github.com/login/device")!
            activity = .authorizing(userCode: verification.userCode, verificationURL: url)

            let token = try await flow.pollForToken(for: verification)
            try Task.checkCancellation()
            try tokens.save(token)
            try await bootstrap()
            connection = .connected
            activity = .idle
        } catch is CancellationError {
            // User backed out (Cancel / swipe-back); the UI already reset. Do
            // not stamp a spurious error over it.
        } catch {
            activity = .error(Self.describe(error))
        }
    }

    /// The user abandoned the device-flow screen. Clears the transient
    /// authorizing state so a later return starts fresh (the task itself is
    /// cancelled by the caller).
    func authorizingAborted() {
        if case .authorizing = activity { activity = .idle }
    }

    /// Finds the user's routine repo (adopting it, at its real default branch,
    /// if it already exists) or creates it private, and remembers the coordinate.
    private func bootstrap() async throws {
        let account = GitHubAccount(tokens: tokens, client: client)
        let login = try await account.currentLogin()
        let name = GitHubSyncSettings.defaultRepoName

        let resolved: GitHubRepoCoordinate
        if let existing = try await account.repository(owner: login, name: name) {
            resolved = existing
        } else {
            resolved = try await account.createRoutineRepository(name: name)
        }
        coordinate = resolved
        GitHubSyncSettings.save(resolved)
    }

    // MARK: - Sync

    /// One foreground sync pass: push new sessions and local template edits,
    /// pull remote changes, merge. Conflicts default to postpone (never
    /// clobber) — an interactive keep-mine/take-theirs prompt is a follow-up.
    /// Safe to call when disconnected (no-ops) and single-flight (a second call
    /// while one is in flight no-ops rather than racing the base snapshot).
    func sync(context: ModelContext, units: WeightUnit) async {
        guard isConnected, let coordinate, !isSyncing else { return }
        activity = .syncing
        do {
            let baseStore = try ApplicationSupportBaseStore()
            let store = GitHubRepoStore(coordinate: coordinate, tokens: tokens, client: client)
            let engine = SyncEngine(store: store, baseStore: baseStore)

            let bundle = try InterchangeMapping.exportBundle(context: context, units: units)
            let local = try Self.localFileMap(for: bundle)
            let outcome = try await engine.sync(local: local)

            if !outcome.pulls.isEmpty {
                let pulled = try InterchangeFiles.bundle(from: outcome.pulls)
                _ = try InterchangeMapping.importBundle(pulled, context: context)
                try context.save()
            }

            lastSyncedAt = Date()
            GitHubSyncSettings.lastSyncedAt = lastSyncedAt
            lastSyncSummary = Self.summarize(outcome)
            activity = .idle
        } catch {
            // A genuine auth failure means the token is dead — drop to
            // disconnected so the UI offers reconnect. Any other failure
            // (network, transient conflict) leaves us CONNECTED with an error
            // banner, so auto-sync keeps trying and "Sync now" stays reachable.
            if Self.isAuthFailure(error) {
                try? tokens.clear()
                GitHubSyncSettings.clearCoordinate()
                coordinate = nil
                connection = .disconnected
                activity = .error("Your GitHub connection expired. Reconnect.")
            } else {
                activity = .error(Self.describe(error))
            }
        }
    }

    func disconnect() {
        try? tokens.clear()
        GitHubSyncSettings.clearCoordinate()
        try? ApplicationSupportBaseStore.reset()
        coordinate = nil
        lastSyncedAt = nil
        lastSyncSummary = nil
        activity = .idle
        connection = config == nil ? .unconfigured : .disconnected
    }

    // MARK: - Local file map (templates + finished sessions)

    /// The full local interchange file map the three-way merge reconciles
    /// against remote. Templates plus finished sessions (append-only, but
    /// carried here so a session already on the remote reads as unchanged
    /// instead of being re-pulled every pass, and an offline-finished one gets
    /// pushed on the next sync).
    static func localFileMap(for bundle: ExportBundle) throws -> [String: Data] {
        var map: [String: Data] = [:]
        for file in try FileLayout.templateFiles(for: bundle) {
            map[file.path] = file.data
        }
        for session in bundle.sessions {
            let placement = try FileLayout.sessionPlacement(for: session) { map[$0] }
            map[placement.path] = placement.data
        }
        return map
    }

    private static func summarize(_ outcome: SyncOutcome) -> String {
        var parts: [String] = []
        if !outcome.pushed.isEmpty { parts.append("pushed \(outcome.pushed.count)") }
        if !outcome.pulls.isEmpty { parts.append("pulled \(outcome.pulls.count)") }
        if !outcome.postponed.isEmpty { parts.append("\(outcome.postponed.count) to resolve") }
        return parts.isEmpty ? "Up to date" : parts.joined(separator: " · ").capitalizedFirst
    }

    private static func isAuthFailure(_ error: Error) -> Bool {
        (error as? GitHubRepoStore.StoreError) == .notAuthenticated
            || (error as? GitHubAccount.AccountError) == .notAuthenticated
    }

    private static func describe(_ error: Error) -> String {
        if let flow = error as? GitHubDeviceFlow.FlowError {
            switch flow {
            case .accessDenied: return "Authorization was declined."
            case .expired: return "The code expired. Try again."
            case .notConfigured: return "GitHub sync isn't set up in this build yet."
            case .server, .http, .malformedResponse: return "GitHub couldn't complete sign-in. Try again."
            }
        }
        if let store = error as? GitHubRepoStore.StoreError {
            switch store {
            case .notAuthenticated: return "Your GitHub connection expired. Reconnect."
            case .conflict: return "The repo changed mid-sync. Try again."
            case .notFound: return "Couldn't find the repo. Reconnect to recreate it."
            case .malformedResponse, .http: return "GitHub returned something unexpected. Try again."
            }
        }
        if let account = error as? GitHubAccount.AccountError {
            switch account {
            case .notAuthenticated: return "Your GitHub connection expired. Reconnect."
            case .malformedResponse, .http: return "GitHub returned something unexpected. Try again."
            }
        }
        return "Something went wrong. Try again."
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

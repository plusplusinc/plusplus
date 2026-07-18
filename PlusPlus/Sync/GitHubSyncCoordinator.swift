import Foundation
import SwiftData
import OSLog
import PlusPlusKit

private let syncLog = Logger(subsystem: "com.davidcole.plusplus", category: "github-sync")

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
    /// True when disconnected because a connect attempt failed or a live
    /// connection expired/broke (not a clean, never-connected state). Drives
    /// the red "disconnected" trigger and starts a reconnect on the authorize
    /// step (the repo + App install already exist). Meaningless while connected.
    private(set) var faulted: Bool = false
    /// A short human line about the last pass ("Pushed 3 · pulled 1").
    private(set) var lastSyncSummary: String?

    private let config: GitHubAppConfiguration?
    private let tokens: any TokenStore
    private let client: any HTTPClient

    init(
        config: GitHubAppConfiguration? = GitHubSyncSettings.appConfiguration,
        tokens: any TokenStore = KeychainTokenStore(),
        // Retry transient network failures — notably URLError -1005
        // (connection lost), which fires on the first request after the app
        // returns from the Safari authorization round-trip.
        client: any HTTPClient = RetryingHTTPClient(wrapping: URLSessionHTTPClient())
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
        // A live connection is never in a fault state; the persisted flag only
        // matters while disconnected (never-connected gray vs broke-off red).
        faulted = connection == .connected ? false : GitHubSyncSettings.connectionFaulted
    }

    private func setFault() {
        faulted = true
        GitHubSyncSettings.connectionFaulted = true
    }

    private func clearFault() {
        faulted = false
        GitHubSyncSettings.connectionFaulted = false
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
            // Prefer the pre-filled URL (code already embedded) so the user
            // just taps Authorize; fall back to the plain page + the code.
            let urlString = verification.verificationURIComplete ?? verification.verificationURI
            let url = URL(string: urlString) ?? URL(string: "https://github.com/login/device")!
            activity = .authorizing(userCode: verification.userCode, verificationURL: url)

            let token = try await flow.pollForToken(for: verification)
            try Task.checkCancellation()
            try tokens.save(token)
            try await bootstrap()
            connection = .connected
            activity = .idle
            clearFault()
        } catch is CancellationError {
            // User backed out (Cancel / swipe-back); the UI already reset. Do
            // not stamp a spurious error over it.
        } catch {
            syncLog.error("connect failed: \(String(reflecting: error), privacy: .public)")
            activity = .error(Self.describe(error))
            // A missing/uninstalled repo is an unfinished setup, not a broken
            // connection: don't flag the trigger red or force the next open
            // onto the authorize step (the user still needs the install step).
            // The in-tray error already names what to do. Every other failure
            // (declined, expired, network) is a genuine failed attempt → fault.
            if !(error is BootstrapError) { setFault() }
        }
    }

    /// The user abandoned the device-flow screen. Clears the transient
    /// authorizing state so a later return starts fresh (the task itself is
    /// cancelled by the caller).
    func authorizingAborted() {
        if case .authorizing = activity { activity = .idle }
    }

    enum BootstrapError: Error { case repositoryUnavailable }

    /// Adopts whichever repo the App is installed on (discovered from the
    /// installation, so it can be named anything and we can only ever target a
    /// repo the App actually has access to). The Contents-only App can't create
    /// a repo, so the user pre-creates one and installs PlusPlus Sync on it; an
    /// empty result means they haven't yet — surface an actionable message.
    private func bootstrap() async throws {
        let account = GitHubAccount(tokens: tokens, client: client)
        let repos = try await account.installedRepositories()
        guard !repos.isEmpty else { throw BootstrapError.repositoryUnavailable }

        // Keep syncing the same repo across reconnects if it's still installed;
        // otherwise take the first (a personal install is a single repo).
        let chosen: GitHubRepoCoordinate
        if let saved = coordinate, repos.contains(saved) {
            chosen = saved
        } else {
            chosen = repos[0]
        }
        coordinate = chosen
        GitHubSyncSettings.save(chosen)
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
            let store = GitHubRepoStore(
                coordinate: coordinate, tokens: tokens, client: client,
                // Content-addressed by git SHA — without it every pass
                // re-downloads the whole history archive, and GPX sidecars
                // (#378) multiply that.
                blobCache: DiskBlobCache()
            )
            let engine = SyncEngine(store: store, baseStore: baseStore)

            let orphans = OrphanSidecarStore()
            let bundle = try InterchangeMapping.exportBundle(context: context, units: units)
            let local = try Self.localFileMap(
                for: bundle,
                routes: Self.routeSidecars(context: context),
                orphans: orphans?.all() ?? [:]
            )
            let outcome = try await engine.sync(local: local)

            if !outcome.pulls.isEmpty {
                let pulled = try InterchangeFiles.bundle(from: outcome.pulls)
                _ = try InterchangeMapping.importBundle(pulled, context: context)
                // Sidecars skip the bundle path by design; pair + attach
                // them after the sessions they belong to exist (#378).
                // Unplaceable ones are BANKED, not dropped — their bytes
                // must keep appearing in the local map or the dirty gate
                // reads them as a change forever.
                for leftover in RouteSidecars.attach(pulls: outcome.pulls, context: context) {
                    orphans?.save(path: leftover.path, data: leftover.data)
                }
                try context.save()
            }
            // Retry banked orphans — their session may exist now (this
            // pass's import, or a bundle import between passes). Attached
            // entries leave the bank; their session serves the path.
            if let orphans {
                let banked = orphans.all().map { FileWrite(path: $0.key, data: $0.value) }
                if !banked.isEmpty {
                    let still = Set(RouteSidecars.attach(pulls: banked, context: context).map(\.path))
                    for entry in banked where !still.contains(entry.path) {
                        orphans.remove(path: entry.path)
                    }
                    try context.save()
                }
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
                self.coordinate = nil
                connection = .disconnected
                activity = .error("Your GitHub connection expired. Reconnect.")
                setFault()
            } else {
                syncLog.error("sync failed: \(String(reflecting: error), privacy: .public)")
                activity = .error(Self.describe(error))
            }
        }
    }

    // MARK: - Boundary sync (debounced, dirty-gated)

    @ObservationIgnored private var pendingSyncTask: Task<Void, Never>?

    /// A sync triggered by an edit boundary (leaving the catalog, an editor, a
    /// routine). Two properties the always-runs `sync()` deliberately lacks:
    /// it's **debounced**, so a burst of edits (toggle several items, then close
    /// the screen) coalesces into ONE commit; and it's **dirty-gated**, doing a
    /// cheap network-free diff of local-vs-base and only reaching GitHub when
    /// there's actually something to push. So merely opening a routine and
    /// backing out costs nothing. Pulling remote changes stays on `sync()`
    /// (foreground, pull-to-refresh); this never fetches on a no-op.
    func requestSync(context: ModelContext, units: WeightUnit) {
        guard isConnected else { return }
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            // If a pass is mid-flight, single-flight would drop THIS one and the
            // just-made edit would wait for the next trigger. Wait it out, then
            // re-check dirtiness and push, so a boundary edit can't be lost to a
            // race with the foreground/Sync-now pass.
            while isSyncing {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            guard Self.hasLocalChanges(context: context, units: units) else { return }
            await sync(context: context, units: units)
        }
    }

    /// Cheap, network-free: does the local program differ from the base snapshot
    /// saved at the last sync? True when there's something to push. Errs toward
    /// syncing if it can't tell (the pass itself is safe and single-flighted).
    private static func hasLocalChanges(context: ModelContext, units: WeightUnit) -> Bool {
        do {
            let base = try ApplicationSupportBaseStore().loadBase()
            if base.isEmpty { return true }   // never synced → a first pass matters
            let bundle = try InterchangeMapping.exportBundle(context: context, units: units)
            // Routes AND banked orphans included — the base carries sidecars
            // after a sync, so a map built without them would read as dirty
            // forever.
            let local = try localFileMap(
                for: bundle,
                routes: routeSidecars(context: context),
                orphans: OrphanSidecarStore()?.all() ?? [:]
            )
            return local != base
        } catch {
            return true
        }
    }

    func disconnect() {
        try? tokens.clear()
        GitHubSyncSettings.clearCoordinate()
        try? ApplicationSupportBaseStore.reset()
        // Repo-derived caches go with the connection.
        OrphanSidecarStore.reset()
        DiskBlobCache.reset()
        coordinate = nil
        lastSyncedAt = nil
        lastSyncSummary = nil
        activity = .idle
        connection = config == nil ? .unconfigured : .disconnected
        // A deliberate disconnect is clean, not a breakage: back to gray.
        clearFault()
    }

    // MARK: - Local file map (templates + finished sessions)

    /// The full local interchange file map the three-way merge reconciles
    /// against remote. Templates plus finished sessions (append-only, but
    /// carried here so a session already on the remote reads as unchanged
    /// instead of being re-pulled every pass, and an offline-finished one gets
    /// pushed on the next sync). `routes` carries each GPS session's sidecar
    /// bytes VERBATIM (#378) — they must appear in EVERY map or the planner
    /// re-pulls them each pass, and they must never be re-encoded or the
    /// byte-diff churns.
    static func localFileMap(
        for bundle: ExportBundle,
        routes: [String: Data] = [:],
        orphans: [String: Data] = [:]
    ) throws -> [String: Data] {
        var map: [String: Data] = [:]
        for file in try FileLayout.templateFiles(for: bundle) {
            map[file.path] = file.data
        }
        for session in bundle.sessions {
            let placement = try FileLayout.sessionPlacement(for: session) { map[$0] }
            map[placement.path] = placement.data
            if let gpx = routes[Self.routeKey(session.routineName, session.startedAt)] {
                map[FileLayout.routeSidecarPath(forSessionPath: placement.path)] = gpx
            }
        }
        // Banked orphan sidecars: bytes we pulled but couldn't attach yet.
        // Carrying them keeps the map equal to the base (no phantom dirt);
        // a session-owned path always wins.
        for (path, data) in orphans where map[path] == nil {
            map[path] = data
        }
        return map
    }

    /// The stored sidecar bytes of every finished GPS session, keyed to pair
    /// with the bundle's DTOs inside `localFileMap`. The predicate touches
    /// only `endedAt` — `routeData` is an `.externalStorage` attribute, and
    /// external-binary columns are not reliably queryable in predicates
    /// (a silent translation failure here would no-op the whole feature,
    /// swift-reviewer catch) — the route filter runs in memory.
    static func routeSidecars(context: ModelContext) -> [String: Data] {
        let sessions = (try? context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil })
        )) ?? []
        return Dictionary(
            sessions.compactMap { session in
                session.routeData.map { (Self.routeKey(session.routineName, session.startedAt), $0) }
            },
            // Same name + same start can't import twice (the dedupe key),
            // but never crash on a weird store — first wins.
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func routeKey(_ routineName: String, _ startedAt: Date) -> String {
        "\(routineName.lowercased())|\(startedAt.timeIntervalSince1970)"
    }

    /// A short, friendly line about the last pass — for the pull-to-refresh
    /// toast. Getting new data wins the label, then backing up, else nothing
    /// changed. Deliberately plain language, not counts or git verbs (Dave).
    private static func summarize(_ outcome: SyncOutcome) -> String {
        if !outcome.pulls.isEmpty { return "Updated from GitHub" }
        if !outcome.pushed.isEmpty { return "Backed up" }
        return "Up to date"
    }

    private static func isAuthFailure(_ error: Error) -> Bool {
        (error as? GitHubRepoStore.StoreError) == .notAuthenticated
            || (error as? GitHubAccount.AccountError) == .notAuthenticated
    }

    private static func describe(_ error: Error) -> String {
        if error is BootstrapError {
            return "Install PlusPlus Sync on a repo (GitHub → PlusPlus Sync → Configure), then reconnect."
        }
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
            case .malformedResponse: return "GitHub returned something unexpected. Try again."
            case .http(let status, _): return "GitHub returned HTTP \(status). Try again."
            }
        }
        if let account = error as? GitHubAccount.AccountError {
            switch account {
            case .notAuthenticated: return "Your GitHub connection expired. Reconnect."
            case .malformedResponse: return "GitHub returned something unexpected. Try again."
            case .http(let status, _): return "GitHub returned HTTP \(status). Try again."
            }
        }
        if let urlError = error as? URLError {
            return "Network error (\(urlError.code.rawValue)). Check your connection and try again."
        }
        if let keychain = error as? KeychainTokenStore.KeychainError, case .status(let code) = keychain {
            return "Couldn't save the token (Keychain \(code)). Try again."
        }
        // Last resort: surface the concrete error so on-device testing can name
        // the cause instead of guessing.
        return "Couldn't connect: \(error)"
    }
}

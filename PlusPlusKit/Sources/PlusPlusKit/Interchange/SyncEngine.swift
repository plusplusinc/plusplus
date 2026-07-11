import Foundation

/// The transport a sync runs against. The app's GitHub adapter (#23)
/// implements this over the contents/git-data REST APIs; the CLI could
/// implement it over a clone; tests use an in-memory fake. Implementations
/// own their consistency story (e.g. SHA-based optimistic concurrency) —
/// the engine only sees file maps.
public protocol RepoStore {
    /// Every interchange file currently in the repo: path → bytes.
    func fetchAll() async throws -> [String: Data]

    /// Apply creates/updates as one commit with the given message.
    func write(_ files: [FileWrite], message: String) async throws
}

/// Persists the base snapshot — the file state as of the last completed
/// sync — that `SyncPlanner`'s three-way merge pivots on. On the phone
/// this will be a directory under Application Support; in tests, a
/// dictionary.
public protocol SyncBaseStore {
    func loadBase() throws -> [String: Data]
    func saveBase(_ files: [String: Data]) throws
}

/// What to do with one conflicted path. `postpone` leaves the path out of
/// the new base, so it conflicts again on the next pass — "ask me later".
public enum ConflictChoice: Sendable {
    case keepMine
    case takeTheirs
    case postpone
}

/// What one sync pass did. `pulls` carry the remote bytes the caller must
/// apply locally (via `InterchangeMapping` in the app); the engine assumes
/// they are applied and records them in the new base accordingly.
public struct SyncOutcome: Equatable, Sendable {
    public var pushed: [String] = []
    public var pulls: [FileWrite] = []
    public var postponed: [String] = []
    /// Message of the commit made this pass, nil when nothing was pushed.
    public var commitMessage: String?

    public init() {}
}

/// Orchestrates one template-sync pass: load base → fetch remote → plan →
/// resolve conflicts → push → save the converged base. Pure with respect
/// to transports and storage, so the whole state machine tests on Linux
/// against fakes; the app supplies real stores and applies `pulls`.
///
/// Finished sessions don't go through `sync` — they're append-only. Use
/// `pushSession`, which places the file via `FileLayout.sessionPlacement`
/// and never rewrites existing history.
public struct SyncEngine {
    private let store: any RepoStore
    private let baseStore: any SyncBaseStore

    public init(store: any RepoStore, baseStore: any SyncBaseStore) {
        self.store = store
        self.baseStore = baseStore
    }

    @discardableResult
    public func sync(
        local: [String: Data],
        resolving: (String) -> ConflictChoice = { _ in .postpone }
    ) async throws -> SyncOutcome {
        let base = try baseStore.loadBase()
        let remote = try await store.fetchAll()
        let plan = SyncPlanner.plan(local: local, remote: remote, base: base)

        var outcome = SyncOutcome()
        var writes = plan.writes
        // Pulls carry the bytes the app must adopt — remote content for
        // remote-authored files, merged content for auto-merged conflicts.
        var pulls: [FileWrite] = plan.pulls.compactMap { path in
            remote[path].map { FileWrite(path: path, data: $0) }
        }

        for path in plan.conflicts {
            // A both-sides change is a conflict only if the SAME fields
            // collided. Try a field-level three-way merge first: disjoint
            // edits converge automatically (local-wins on a true same-field
            // collision), so almost nothing reaches the resolving closure.
            if let localData = local[path], let remoteData = remote[path],
               let merged = TemplateMerge.merge(base: base[path], local: localData, remote: remoteData, path: path) {
                if remoteData != merged { writes.append(FileWrite(path: path, data: merged)) }
                if localData != merged { pulls.append(FileWrite(path: path, data: merged)) }
                continue
            }
            // Un-mergeable (unknown shape / undecodable): fall back to the
            // caller's keep-mine/take-theirs/postpone decision.
            switch resolving(path) {
            case .keepMine:
                if let data = local[path] {
                    writes.append(FileWrite(path: path, data: data))
                }
            case .takeTheirs:
                if let data = remote[path] {
                    pulls.append(FileWrite(path: path, data: data))
                }
            case .postpone:
                outcome.postponed.append(path)
            }
        }
        writes.sort { $0.path < $1.path }
        pulls.sort { $0.path < $1.path }

        if !writes.isEmpty {
            let message = Self.commitMessage(pushing: writes.map(\.path))
            try await store.write(writes, message: message)
            outcome.commitMessage = message
        }
        outcome.pushed = writes.map(\.path)
        outcome.pulls = pulls

        // The converged state becomes the next base. Postponed conflicts
        // keep their old base entry (or stay absent) so they re-conflict.
        var newBase: [String: Data] = [:]
        for write in writes { newBase[write.path] = write.data }
        for pull in pulls { newBase[pull.path] = pull.data }
        for path in plan.unchanged { newBase[path] = local[path] }
        for path in outcome.postponed { newBase[path] = base[path] }
        try baseStore.saveBase(newBase)

        return outcome
    }

    /// Pushes one finished session append-only. Returns the path written,
    /// or nil when identical content is already in the repo (idempotent —
    /// safe to retry after a network failure).
    @discardableResult
    public func pushSession(_ session: SessionDTO) async throws -> String? {
        let remote = try await store.fetchAll()
        let placement = try FileLayout.sessionPlacement(for: session) { remote[$0] }
        if placement.alreadyPresent { return nil }

        let (_, stamp) = FileLayout.utcDateParts(of: session.startedAt)
        let completed = session.sets.filter { $0.completedAt != nil }.count
        let sets = completed == 1 ? "1 set" : "\(completed) sets"
        try await store.write(
            [FileWrite(path: placement.path, data: placement.data)],
            message: "Log: \(session.routineName) — \(sets) (\(stamp))"
        )
        return placement.path
    }

    /// "Sync: push-day, band-pulses (+3 more)" — enough to make repo
    /// history scannable without dumping every path.
    public static func commitMessage(pushing paths: [String]) -> String {
        let names = paths.map { path in
            let file = path.split(separator: "/").last.map(String.init) ?? path
            return file.hasSuffix(".json") ? String(file.dropLast(5)) : file
        }
        let shown = names.prefix(2).joined(separator: ", ")
        let extra = names.count - min(names.count, 2)
        return extra > 0 ? "Sync: \(shown) (+\(extra) more)" : "Sync: \(shown)"
    }
}

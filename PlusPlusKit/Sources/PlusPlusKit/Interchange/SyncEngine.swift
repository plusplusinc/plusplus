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

        // First sync on this install (no base) against a populated repo is a
        // RESTORE, not a merge. A fresh install seeds default/empty state (an
        // empty "Home" library, the un-adopted catalog), and with no base the
        // three-way merge can't tell that emptiness from a deliberate edit — so
        // a plain merge lets the seed's empty fields win and WIPES real data in
        // the repo (the reinstall-erased-my-equipment bug). Instead: adopt every
        // remote file, and push only local files the repo doesn't have. Once the
        // base is saved, every later pass is a normal three-way merge.
        if base.isEmpty && !remote.isEmpty {
            return try await restore(local: local, remote: remote)
        }

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

    /// First-sync restore: the repo is the source of truth. Adopt every remote
    /// file (the caller applies `pulls` locally), push only local-only files
    /// (real work made before connecting — a fresh reinstall has none), and
    /// save the converged state as the base. Never overwrites a remote file, so
    /// a fresh install can't wipe the backup it's restoring from.
    private func restore(local: [String: Data], remote: [String: Data]) async throws -> SyncOutcome {
        var outcome = SyncOutcome()
        var newBase: [String: Data] = [:]
        var pulls: [FileWrite] = []
        for (path, data) in remote {
            newBase[path] = data
            if local[path] != data {
                pulls.append(FileWrite(path: path, data: data))
            }
        }
        let writes = local
            .filter { remote[$0.key] == nil }
            .map { FileWrite(path: $0.key, data: $0.value) }
            .sorted { $0.path < $1.path }
        for write in writes { newBase[write.path] = write.data }

        if !writes.isEmpty {
            let message = Self.commitMessage(pushing: writes.map(\.path))
            try await store.write(writes, message: message)
            outcome.commitMessage = message
        }
        outcome.pushed = writes.map(\.path)
        outcome.pulls = pulls.sorted { $0.path < $1.path }
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

    /// A human commit subject derived from WHAT changed, not just which files:
    /// "Update equipment: barbell", "Update 2 routines", "Log workout", and
    /// "Sync 4 changes" when a single pass spans more than one area. The paths
    /// already carry the category (the interchange layout), so the message needs
    /// no intent hint threaded from the call site — every commit reads cleanly
    /// in the repo history on its own.
    public static func commitMessage(pushing paths: [String]) -> String {
        var buckets: [PathCategory: Set<String>] = [:]
        for path in paths {
            // A Set, not an array: a session and its GPX route sidecar
            // (#378) share a basename and are ONE logical workout — a run
            // must commit as "Log workout", not "Log 2 workouts".
            buckets[PathCategory(path: path), default: []].insert(fileName(of: path))
        }
        guard buckets.count == 1, let (category, names) = buckets.first else {
            let total = paths.count
            return "Sync \(total) change\(total == 1 ? "" : "s")"
        }
        return category.message(names: names.sorted())
    }

    private static func fileName(of path: String) -> String {
        let file = path.split(separator: "/").last.map(String.init) ?? path
        if file.hasSuffix(".json") { return String(file.dropLast(5)) }
        if file.hasSuffix(".gpx") { return String(file.dropLast(4)) }
        return file
    }

    /// Which interchange area a synced path belongs to, for commit-message copy.
    /// Equipment and equipment-libraries fold into one "equipment" idea.
    private enum PathCategory: Hashable {
        case equipment, exercises, routines, history, other

        init(path: String) {
            if path.hasPrefix(FileLayout.equipmentDirectory + "/") ||
               path.hasPrefix(FileLayout.equipmentLibrariesDirectory + "/") {
                self = .equipment
            } else if path.hasPrefix(FileLayout.exercisesDirectory + "/") {
                self = .exercises
            } else if path.hasPrefix(FileLayout.routinesDirectory + "/") {
                self = .routines
            } else if path.hasPrefix(FileLayout.historyDirectory + "/") {
                self = .history
            } else {
                self = .other
            }
        }

        func message(names: [String]) -> String {
            let n = names.count
            switch self {
            case .equipment:
                return n == 1 ? "Update equipment: \(names[0])" : "Update equipment (\(n) items)"
            case .exercises:
                return n == 1 ? "Update exercise: \(names[0])" : "Update \(n) exercises"
            case .routines:
                return n == 1 ? "Update routine: \(names[0])" : "Update \(n) routines"
            case .history:
                // History filenames are date-stamped slugs, too noisy to name.
                return n == 1 ? "Log workout" : "Log \(n) workouts"
            case .other:
                return n == 1 ? "Sync \(names[0])" : "Sync \(n) changes"
            }
        }
    }
}

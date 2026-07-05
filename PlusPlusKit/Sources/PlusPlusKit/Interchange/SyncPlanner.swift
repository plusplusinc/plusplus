import Foundation

/// A planned write to the remote (create or update).
public struct FileWrite: Equatable, Sendable {
    public let path: String
    public let data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// The template half of a sync pass (docs/PLATFORM.md sync semantics).
/// Sessions never appear here — they're append-only via
/// `FileLayout.sessionPlacement` and cannot conflict.
public struct SyncPlan: Equatable, Sendable {
    /// Local wins: push these to the remote.
    public var writes: [FileWrite] = []
    /// Remote wins: the app should adopt these paths' remote content.
    public var pulls: [String] = []
    /// Changed on both sides since the last sync — ask the user
    /// (keep mine / take theirs).
    public var conflicts: [String] = []
    public var unchanged: [String] = []

    public init() {}
}

/// Pure three-way merge over template files, per path. The transports
/// (GitHub API in the app, git in the CLI) supply the three file maps; this
/// decides what happens. Deletions are out of scope for v1 — a path absent
/// locally but present remotely is treated as remote-authored (pull), never
/// as a delete.
public enum SyncPlanner {
    public static func plan(
        local: [String: Data],
        remote: [String: Data],
        base: [String: Data]
    ) -> SyncPlan {
        var plan = SyncPlan()
        let allPaths = Set(local.keys).union(remote.keys).sorted()

        for path in allPaths {
            let localData = local[path]
            let remoteData = remote[path]
            let baseData = base[path]

            switch (localData, remoteData) {
            case (nil, nil):
                continue
            case (let localData?, nil):
                // New locally (or never synced): push it.
                plan.writes.append(FileWrite(path: path, data: localData))
            case (nil, _?):
                // Exists only remotely: created elsewhere — adopt it.
                plan.pulls.append(path)
            case (let localData?, let remoteData?):
                if localData == remoteData {
                    plan.unchanged.append(path)
                } else if remoteData == baseData {
                    // Remote untouched since last sync: local edit wins.
                    plan.writes.append(FileWrite(path: path, data: localData))
                } else if localData == baseData {
                    // Local untouched: remote edit wins.
                    plan.pulls.append(path)
                } else {
                    plan.conflicts.append(path)
                }
            }
        }
        return plan
    }
}

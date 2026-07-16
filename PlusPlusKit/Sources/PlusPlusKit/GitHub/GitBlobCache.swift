import Foundation

/// A content-addressed cache for git blobs, keyed by the SHA GitHub already
/// returns in every tree listing (#378 PR 3). `fetchAll` re-downloads every
/// synced blob on every pass today; history grows monotonically and GPX
/// route sidecars are ~100× the size of a session JSON, so without a cache
/// each sync pass re-pays the whole archive. Git SHAs are content-addressed,
/// so a hit can never be stale — no invalidation story needed, and no local
/// SHA computation either (the tree supplies it).
///
/// Implementations own their bounds/eviction (the app uses a size-capped
/// disk directory); the store treats the cache as advisory — a miss just
/// fetches.
public protocol GitBlobCache: Sendable {
    func data(forSHA sha: String) -> Data?
    func store(_ data: Data, sha: String)
}

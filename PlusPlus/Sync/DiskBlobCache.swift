import Foundation
import PlusPlusKit

/// The app's `GitBlobCache`: one file per git SHA under Caches/BlobCache
/// (#378 PR 3). Content-addressed, so entries are immutable — no
/// invalidation, just a size cap. Eviction is oldest-access-first,
/// approximated by file modification date (a hit re-stamps it), checked
/// lazily on store so the hot read path never scans the directory.
///
/// Losing this directory is always safe: the next sync re-fetches — which
/// is exactly why it lives in Caches (never backed up, purgeable by the
/// system under pressure), per Apple's data-storage guidance for
/// re-derivable content.
final class DiskBlobCache: GitBlobCache, @unchecked Sendable {
    /// ~50 MB holds years of session JSON plus hundreds of GPX sidecars.
    private let capBytes: Int
    private let directory: URL
    private let queue = DispatchQueue(label: "com.davidcole.plusplus.blob-cache")

    init?(capBytes: Int = 50_000_000) {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        directory = caches.appendingPathComponent("BlobCache", isDirectory: true)
        self.capBytes = capBytes
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
    }

    /// Disconnect hygiene — repo-derived bytes go with the connection.
    static func reset() {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("BlobCache", isDirectory: true))
    }

    func data(forSHA sha: String) -> Data? {
        guard Self.isSafe(sha) else { return nil }
        return queue.sync {
            let url = directory.appendingPathComponent(sha)
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Re-stamp so eviction approximates LRU.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return data
        }
    }

    func store(_ data: Data, sha: String) {
        guard Self.isSafe(sha) else { return }
        queue.sync {
            let url = directory.appendingPathComponent(sha)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            evictIfNeeded()
        }
    }

    /// A git SHA is strictly hex — anything else must not become a path
    /// component (defense against a malformed tree response).
    private static func isSafe(_ sha: String) -> Bool {
        !sha.isEmpty && sha.count <= 64 && sha.allSatisfy(\.isHexDigit)
    }

    /// Runs on `queue`. Scans only after a write; drops oldest-modified
    /// entries until back under the cap.
    private func evictIfNeeded() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        ) else { return }
        var entries: [(url: URL, size: Int, modified: Date)] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > capBytes else { return }
        entries.sort { $0.modified < $1.modified }
        for entry in entries {
            guard total > capBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

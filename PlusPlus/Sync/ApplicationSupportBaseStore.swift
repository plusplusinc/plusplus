import Foundation
import PlusPlusKit

/// The phone's `SyncBaseStore`: the last-synced file snapshot the three-way
/// merge pivots on, persisted as a single JSON file under Application Support
/// (excluded from iCloud/iTunes backup — it's a cache, rebuildable by a fresh
/// full sync). Path bytes are base64 in the JSON so arbitrary file content
/// survives the round-trip.
struct ApplicationSupportBaseStore: SyncBaseStore {
    private let fileURL: URL

    init(fileName: String = "github-sync-base.json") throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        var directory = support.appendingPathComponent("Sync", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep the base out of backups — it's a derived cache.
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? directory.setResourceValues(resourceValues)
        self.fileURL = directory.appendingPathComponent(fileName)
    }

    func loadBase() throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let raw = try Data(contentsOf: fileURL)
        let encoded = try JSONDecoder().decode([String: String].self, from: raw)
        var base: [String: Data] = [:]
        for (path, b64) in encoded {
            base[path] = Data(base64Encoded: b64) ?? Data()
        }
        return base
    }

    func saveBase(_ files: [String: Data]) throws {
        var encoded: [String: String] = [:]
        for (path, data) in files {
            encoded[path] = data.base64EncodedString()
        }
        let raw = try JSONEncoder().encode(encoded)
        try raw.write(to: fileURL, options: .atomic)
    }

    /// Drop the cached base — used on disconnect, so a later reconnect starts
    /// from a clean full sync rather than a stale pivot.
    static func reset() throws {
        let store = try ApplicationSupportBaseStore()
        try? FileManager.default.removeItem(at: store.fileURL)
    }
}

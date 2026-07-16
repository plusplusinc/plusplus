import Foundation

/// Pulled GPX sidecars that couldn't pair with a session yet (#378) — a
/// foreign hand-dropped file, or a sidecar whose session JSON didn't
/// materialize this pass. Holding the bytes locally keeps the sync file
/// map equal to the saved base (without this, an unattachable sidecar
/// reads as a local change FOREVER: every edit boundary escalates to a
/// full network pass and every pass re-pulls it — swift-reviewer catch),
/// and each sync retries the pairing; an entry is deleted the moment its
/// bytes live on a session, whose `routeData` then serves the path.
///
/// One file per sidecar under Application Support/OrphanSidecars; the
/// repo-relative path is the filename with "/" swapped for "|" (never in
/// a slug, legal on-disk) — trivially reversible for `all()`.
struct OrphanSidecarStore {
    private let directory: URL

    init?() {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        directory = support.appendingPathComponent("OrphanSidecars", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
    }

    func all() -> [String: Data] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [:] }
        return Dictionary(
            urls.compactMap { url in
                (try? Data(contentsOf: url)).map {
                    (url.lastPathComponent.replacingOccurrences(of: "|", with: "/"), $0)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func save(path: String, data: Data) {
        try? data.write(to: fileURL(for: path), options: .atomic)
    }

    func remove(path: String) {
        try? FileManager.default.removeItem(at: fileURL(for: path))
    }

    private func fileURL(for path: String) -> URL {
        directory.appendingPathComponent(path.replacingOccurrences(of: "/", with: "|"))
    }

    /// Disconnect hygiene: orphans are repo bytes; a cleared connection
    /// clears them (a reconnect re-pulls whatever still matters).
    static func reset() {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        try? FileManager.default.removeItem(at: support.appendingPathComponent("OrphanSidecars", isDirectory: true))
    }
}

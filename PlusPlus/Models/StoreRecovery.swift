import Foundation

/// #155 recovery: a store the app cannot open is PRESERVED (its raw
/// bytes, in a Files-visible folder) BEFORE anything is deleted, and a
/// breadcrumb is left so the app can tell the user their data was reset
/// rather than pretending nothing happened. Never a silent wipe.
///
/// Prevention does the real work — the `AppMigrationPlan` means ordinary
/// shape changes migrate rather than land here — so this path is for
/// genuine corruption or a store the plan can't map. When it does run,
/// the raw copy is the guaranteed salvage (it can't fail on a corrupt
/// store and loses zero bytes); a friendlier interchange-JSON export +
/// in-app re-import is deferred (it needs a readable context this path
/// may not have, and GitHub sync is the real "never lose a rep" restore).
enum StoreRecovery {
    /// The SQLite store plus its write-ahead sidecars.
    static let sidecarSuffixes = ["", "-shm", "-wal"]

    /// Copy the unopenable store aside, then delete the live files so the
    /// caller can recreate a fresh one, and leave a breadcrumb. Best-effort
    /// throughout: a copy that fails still leaves the delete+recreate to
    /// unbrick the app; a delete that fails is retried by the OS next launch.
    static func backUpAndReset(storeURL: URL, error: Error) {
        let fm = FileManager.default

        // A per-incident folder in Documents (Files-visible via the
        // Info.plist file-sharing keys), named by wall-clock seconds so
        // repeated incidents don't collide.
        let backupDir = fm.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("RecoveredStore-\(Int(Date().timeIntervalSince1970))", isDirectory: true)

        // Track whether the MAIN store file actually copied — a corrupt
        // store can be caused by a full disk, in which case every copy
        // fails and we must NOT promise the user a backup that doesn't
        // exist. The sidecars are recoverable-nice-to-have; the .sqlite
        // itself is what "a backup was saved" means.
        var mainStoreCopied = false
        if let backupDir {
            try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for suffix in sidecarSuffixes {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = backupDir.appendingPathComponent(src.lastPathComponent)
                do {
                    try fm.copyItem(at: src, to: dst)
                    if suffix.isEmpty { mainStoreCopied = true }
                } catch {
                    // best-effort — a failed copy still leaves the reset to
                    // unbrick the app; we just won't claim a saved backup.
                }
            }
        }

        for suffix in sidecarSuffixes {
            try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }

        SetupState.markStoreReset(backupPath: mainStoreCopied ? backupDir?.path : nil)
    }
}

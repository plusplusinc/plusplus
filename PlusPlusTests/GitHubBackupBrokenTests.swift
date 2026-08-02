import Foundation
import Testing
import PlusPlusKit
@testable import PlusPlus

/// The predicate behind Today's broken-sync advisory (#509, Q19-A).
///
/// ⚠️ These ARE red-first. The first cut gated the advisory on
/// `lastSyncedAt != nil` as its "was this ever working" evidence, and
/// `relaunchAfterExpiredTokenStillReportsBroken` fails against that cut —
/// which is the whole bug: the commonest way a live sync breaks is an
/// expired or revoked token, `sync()` handles that by calling
/// `clearCoordinate()`, and `clearCoordinate()` deletes the last-synced
/// stamp in the same breath as `setFault()` records the fault. The in-memory
/// value survives the current process, so the advisory looked correct in
/// testing and on the day it broke — and then vanished forever at the next
/// launch, exactly while local edits piled up un-pushed.
///
/// `everSynced` is the replacement: written by the first successful pass,
/// cleared only by a deliberate `disconnect()`.
///
/// ⚠️ The state under test is process-global `UserDefaults.standard` — the
/// coordinator hardcodes `.standard` for these keys — so every test RESTORES
/// what it found rather than clearing it (`withRestoredDefaults`, the
/// `LiveWorkoutSettingsTests` pattern). Clearing was the first cut and it is
/// wrong twice over: it wipes a real GitHub connection out from under anyone
/// running the suite against a simulator whose host app was connected, and
/// `.serialized` would not have saved it anyway — that trait orders tests
/// WITHIN this suite, while other suites still run concurrently in the same
/// process against the same defaults. `.serialized` is kept because these
/// tests share one key set with each other; it is not the isolation story.
@Suite("GitHubSyncCoordinator broken-backup predicate", .serialized)
@MainActor
struct GitHubBackupBrokenTests {

    /// A client that refuses to do anything — none of these tests reach the
    /// network, and a stub makes that a compile-time fact rather than a hope.
    private struct UnusedClient: HTTPClient {
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            Issue.record("A predicate test made a network request: \(request.url)")
            throw CancellationError()
        }
    }

    /// Build a coordinator over the CURRENT defaults — the constructor is
    /// what reads them, so calling it again is the test's stand-in for a
    /// relaunch.
    private func relaunch(token: String? = nil) -> GitHubSyncCoordinator {
        GitHubSyncCoordinator(
            config: GitHubAppConfiguration(clientID: "probe-client"),
            tokens: InMemoryTokenStore(token: token),
            client: UnusedClient()
        )
    }

    /// Every defaults key these tests touch. Named explicitly rather than
    /// derived, so adding a key to `GitHubSyncSettings` without adding it
    /// here shows up as a leak rather than passing quietly.
    private static let touchedKeys = [
        "github.sync.owner", "github.sync.repo", "github.sync.branch",
        "github.sync.lastSyncedAt", "github.sync.faulted", "github.sync.everSynced",
    ]

    /// Run `body` over a clean never-connected install, then put every key
    /// back exactly as it was found.
    private func withRestoredDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let originals = Self.touchedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originals {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in Self.touchedKeys { defaults.removeObject(forKey: key) }
        body()
    }

    /// Someone who tried GitHub sync once, failed, and never came back.
    /// `faulted` is true forever, but there is no backup to have broken —
    /// telling them "nothing lost, syncs when you reconnect" would be a
    /// claim about something that never existed.
    @Test("Faulted but never synced is not a broken backup")
    func faultedWithoutHistoryIsNotBroken() {
        withRestoredDefaults {
            GitHubSyncSettings.connectionFaulted = true

            let sync = relaunch()
            #expect(sync.connection == .disconnected)
            // The drawer row still paints red — that is a status on a row
            // you went looking for, a different claim from a card on Today.
            #expect(sync.isFaulted)
            #expect(!sync.isBackupBroken)
        }
    }

    @Test("Faulted after a working sync IS a broken backup")
    func faultedWithHistoryIsBroken() {
        withRestoredDefaults {
            GitHubSyncSettings.connectionFaulted = true
            GitHubSyncSettings.everSynced = true

            let sync = relaunch()
            #expect(sync.isFaulted)
            #expect(sync.isBackupBroken)
        }
    }

    /// The regression this suite exists for. Replays the auth-failure branch
    /// of `sync()`: token cleared, coordinate cleared (which takes the
    /// last-synced stamp with it), fault recorded. Then relaunches.
    @Test("A relaunch after an expired token still reports the broken backup")
    func relaunchAfterExpiredTokenStillReportsBroken() {
        withRestoredDefaults {
            // A working connection: a pass succeeded, so both stamps land.
            GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
            GitHubSyncSettings.lastSyncedAt = Date()
            GitHubSyncSettings.everSynced = true

            // …then the token expires. This is verbatim what the
            // auth-failure branch does, minus the SwiftData work.
            GitHubSyncSettings.clearCoordinate()
            GitHubSyncSettings.connectionFaulted = true
            // ⚠️ The evidence the first cut relied on is gone at this point.
            #expect(GitHubSyncSettings.lastSyncedAt == nil)

            let sync = relaunch()
            #expect(sync.connection == .disconnected)
            #expect(sync.lastSyncedAt == nil)
            #expect(sync.isBackupBroken, "the advisory must survive the relaunch that follows a revoked token")
        }
    }

    /// A deliberate disconnect is the ONE thing that forgets a backup
    /// existed — otherwise the advisory would outlive the feature.
    ///
    /// ⚠️ This test calls the real `disconnect()`, which also resets the
    /// base snapshot, the orphan sidecars and the blob cache on disk. Those
    /// are the host app's own directories and they rebuild themselves, but
    /// it is a genuine side effect: don't add assertions here that depend
    /// on other suites' filesystem state, and don't copy this test as a
    /// template for something that only needs the defaults.
    @Test("Disconnect clears the ever-synced memory")
    func disconnectForgetsTheBackup() {
        withRestoredDefaults {
            GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
            GitHubSyncSettings.lastSyncedAt = Date()
            GitHubSyncSettings.everSynced = true

            let sync = relaunch(token: "probe-token")
            #expect(sync.isConnected)

            sync.disconnect()
            #expect(!sync.everSynced)
            #expect(!GitHubSyncSettings.everSynced)
            #expect(!sync.isBackupBroken)
            // And it stays forgotten across a relaunch.
            #expect(!relaunch().isBackupBroken)
        }
    }

    /// Installs that were already syncing before `everSynced` existed must
    /// not lose the advisory. The last-synced stamp is what proves a pass
    /// completed, and the constructor is the only place to notice.
    @Test("A pre-flag install that SYNCED backfills its ever-synced memory")
    func preFlagInstallBackfills() {
        withRestoredDefaults {
            // What such an install looks like: coordinate + stamp, flag absent.
            GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
            GitHubSyncSettings.lastSyncedAt = Date()
            #expect(!GitHubSyncSettings.everSynced)

            #expect(relaunch(token: "probe-token").everSynced)
        }
    }

    /// ⚠️ The other half of that backfill, and the one the first cut got
    /// wrong (swift-reviewer). A saved coordinate is NOT proof of a
    /// completed pass: `bootstrap()` writes it at connect time, strictly
    /// before the first sync. Someone who finished the wizard on a flaky
    /// network — coordinate saved, first pass failed on the network, app
    /// killed — must not come back claiming a backup exists, or Today will
    /// eventually print "nothing lost" about a repo that has never received
    /// one byte.
    @Test("A coordinate alone does not prove a backup ever existed")
    func coordinateWithoutASyncDoesNotBackfill() {
        withRestoredDefaults {
            GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
            #expect(GitHubSyncSettings.lastSyncedAt == nil)

            #expect(!relaunch(token: "probe-token").everSynced)

            // And so it stays a non-claim once the connection breaks.
            GitHubSyncSettings.clearCoordinate()
            GitHubSyncSettings.connectionFaulted = true
            let broken = relaunch()
            #expect(broken.isFaulted)
            #expect(!broken.isBackupBroken)
        }
    }

    /// A live connection is never "broken", whatever a stale flag says.
    @Test("Connected is never a broken backup")
    func connectedIsNeverBroken() {
        withRestoredDefaults {
            GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
            GitHubSyncSettings.everSynced = true
            GitHubSyncSettings.connectionFaulted = true

            let sync = relaunch(token: "probe-token")
            #expect(sync.isConnected)
            #expect(!sync.isFaulted)
            #expect(!sync.isBackupBroken)
        }
    }

    /// ⚠️ Authorizing must NOT silence the advisory (swift-reviewer). The
    /// reorder put `clearFault()` at the end of step 1, four user actions
    /// before a connection exists — so tapping Today's card, authorizing,
    /// and then closing the tray would have left the fault cleared, the
    /// drawer row painted like a never-connected install, and nothing in
    /// the app able to raise either signal again. This pins the state
    /// `authorize()` leaves behind: a token, and everything else untouched.
    @Test("Holding a token is not the same as being connected")
    func authorizingAloneDoesNotClearTheFault() {
        withRestoredDefaults {
            GitHubSyncSettings.everSynced = true
            GitHubSyncSettings.connectionFaulted = true

            // What `authorize()` leaves behind: a token, no coordinate.
            let sync = relaunch(token: "probe-token")
            #expect(sync.hasToken)
            #expect(sync.connection == .disconnected)
            #expect(sync.isFaulted)
            #expect(sync.isBackupBroken, "the advisory must survive the act of starting the repair")
        }
    }
}

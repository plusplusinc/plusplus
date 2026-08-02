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
/// ⚠️ `.serialized` because the state under test is `UserDefaults.standard`
/// (the coordinator has no injectable defaults for these two keys) and Swift
/// Testing runs suites in parallel. Every test restores what it touched.
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

    /// Every key these tests touch, back to a clean never-connected install.
    private func resetDefaults() {
        GitHubSyncSettings.clearCoordinate()
        GitHubSyncSettings.connectionFaulted = false
        GitHubSyncSettings.everSynced = false
    }

    /// Someone who tried GitHub sync once, failed, and never came back.
    /// `faulted` is true forever, but there is no backup to have broken —
    /// telling them "nothing lost, syncs when you reconnect" would be a
    /// claim about something that never existed.
    @Test("Faulted but never synced is not a broken backup")
    func faultedWithoutHistoryIsNotBroken() {
        resetDefaults()
        defer { resetDefaults() }
        GitHubSyncSettings.connectionFaulted = true

        let sync = relaunch()
        #expect(sync.connection == .disconnected)
        // The drawer row still paints red — that is a status on a row you
        // went looking for, which is a different claim from a card on Today.
        #expect(sync.isFaulted)
        #expect(!sync.isBackupBroken)
    }

    @Test("Faulted after a working sync IS a broken backup")
    func faultedWithHistoryIsBroken() {
        resetDefaults()
        defer { resetDefaults() }
        GitHubSyncSettings.connectionFaulted = true
        GitHubSyncSettings.everSynced = true

        let sync = relaunch()
        #expect(sync.isFaulted)
        #expect(sync.isBackupBroken)
    }

    /// The regression this suite exists for. Replays the auth-failure branch
    /// of `sync()`: token cleared, coordinate cleared (which takes the
    /// last-synced stamp with it), fault recorded. Then relaunches.
    @Test("A relaunch after an expired token still reports the broken backup")
    func relaunchAfterExpiredTokenStillReportsBroken() {
        resetDefaults()
        defer { resetDefaults() }

        // A working connection: a pass succeeded, so both stamps are written.
        GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
        GitHubSyncSettings.lastSyncedAt = Date()
        GitHubSyncSettings.everSynced = true

        // …then the token expires. This is verbatim what the auth-failure
        // branch does, minus the SwiftData work.
        GitHubSyncSettings.clearCoordinate()
        GitHubSyncSettings.connectionFaulted = true
        // ⚠️ The evidence the first cut relied on is gone at this point.
        #expect(GitHubSyncSettings.lastSyncedAt == nil)

        let sync = relaunch()
        #expect(sync.connection == .disconnected)
        #expect(sync.lastSyncedAt == nil)
        #expect(sync.isBackupBroken, "the advisory must survive the relaunch that follows a revoked token")
    }

    /// A deliberate disconnect is the ONE thing that forgets a backup
    /// existed — otherwise the advisory would outlive the feature.
    @Test("Disconnect clears the ever-synced memory")
    func disconnectForgetsTheBackup() {
        resetDefaults()
        defer { resetDefaults() }
        GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
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

    /// Installs that were already syncing before `everSynced` existed must
    /// not lose the advisory. A stored coordinate is proof enough that a
    /// pass succeeded, and the constructor is the only place to notice.
    @Test("A pre-flag install backfills its ever-synced memory")
    func preFlagInstallBackfills() {
        resetDefaults()
        defer { resetDefaults() }
        // What such an install looks like: coordinate saved, flag absent.
        GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
        #expect(!GitHubSyncSettings.everSynced)

        #expect(relaunch(token: "probe-token").everSynced)
    }

    /// A live connection is never "broken", whatever a stale flag says.
    @Test("Connected is never a broken backup")
    func connectedIsNeverBroken() {
        resetDefaults()
        defer { resetDefaults() }
        GitHubSyncSettings.save(GitHubRepoCoordinate(owner: "probe", repo: "probe-data", branch: "main"))
        GitHubSyncSettings.everSynced = true
        GitHubSyncSettings.connectionFaulted = true

        let sync = relaunch(token: "probe-token")
        #expect(sync.isConnected)
        #expect(!sync.isFaulted)
        #expect(!sync.isBackupBroken)
    }
}

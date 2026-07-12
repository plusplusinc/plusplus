import Foundation
import PlusPlusKit

/// Non-secret sync configuration and remembered connection state.
///
/// The GitHub App **client ID** is read from Info.plist (`GitHubAppClientID`),
/// injected there by the build (project.yml). It isn't a secret — device flow
/// needs no client secret — but it doesn't exist until the owner registers the
/// App (issue #23), so until then the value is empty and the connect flow says
/// so rather than hitting GitHub with a blank id.
///
/// The **repo coordinate** (owner/repo/branch) is device state, remembered in
/// UserDefaults after bootstrap. The **token** lives in the Keychain, never here.
enum GitHubSyncSettings {
    /// The default repo name created/adopted on the user's account.
    static let defaultRepoName = "workouts"

    /// The App's install / repo-picker page — where a user installs PlusPlus
    /// Sync on the repo they want to sync to (a prerequisite for connecting,
    /// since sync targets whichever repo the App is installed on).
    static let installURL = URL(string: "https://github.com/apps/plusplus-sync/installations/new")!

    private enum Key {
        static let owner = "github.sync.owner"
        static let repo = "github.sync.repo"
        static let branch = "github.sync.branch"
        static let lastSynced = "github.sync.lastSyncedAt"
        static let faulted = "github.sync.faulted"
    }

    /// The registered GitHub App client ID, or nil until the App exists.
    static func clientID(bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: "GitHubAppClientID") as? String,
              !value.isEmpty,
              // project.yml ships the key with a placeholder so the plist is
              // always well-formed; treat the placeholder as "not set".
              value != "$(GITHUB_APP_CLIENT_ID)",
              !value.hasPrefix("REPLACE_")
        else { return nil }
        return value
    }

    static var appConfiguration: GitHubAppConfiguration? {
        clientID().map(GitHubAppConfiguration.init(clientID:))
    }

    // MARK: - Remembered coordinate

    static func savedCoordinate(defaults: UserDefaults = .standard) -> GitHubRepoCoordinate? {
        guard let owner = defaults.string(forKey: Key.owner),
              let repo = defaults.string(forKey: Key.repo) else { return nil }
        let branch = defaults.string(forKey: Key.branch) ?? "main"
        return GitHubRepoCoordinate(owner: owner, repo: repo, branch: branch)
    }

    static func save(_ coordinate: GitHubRepoCoordinate, defaults: UserDefaults = .standard) {
        defaults.set(coordinate.owner, forKey: Key.owner)
        defaults.set(coordinate.repo, forKey: Key.repo)
        defaults.set(coordinate.branch, forKey: Key.branch)
    }

    static func clearCoordinate(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Key.owner)
        defaults.removeObject(forKey: Key.repo)
        defaults.removeObject(forKey: Key.branch)
        defaults.removeObject(forKey: Key.lastSynced)
    }

    static var lastSyncedAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Key.lastSynced)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.lastSynced)
        }
    }

    /// A connection was attempted and failed, or a live connection expired or
    /// broke. Distinguishes the "was working, now needs reconnect" state (red
    /// dot, "disconnected") from a clean never-connected install (gray dot).
    /// Survives relaunches because an expired token is cleared on failure, so
    /// nothing else would remember the connection had ever existed. Set on
    /// failure, cleared on a clean connect or a deliberate disconnect.
    static var connectionFaulted: Bool {
        get { UserDefaults.standard.bool(forKey: Key.faulted) }
        set { UserDefaults.standard.set(newValue, forKey: Key.faulted) }
    }
}

import Foundation
import HealthKit
import Observation

/// The reactive face of the Apple Health integration for Settings (the
/// SYNC section, mirroring `GitHubSyncCoordinator` and
/// `CalendarSyncCoordinator`). Holds the user's on/off intent and the one
/// honest system signal HealthKit will actually reveal, and drives the
/// status row + the config tray.
///
/// **HealthKit hides read authorization by design** (a privacy guarantee:
/// an app can never tell whether its read requests were granted). So the
/// only truthful status we can surface is the WRITE side — whether the app
/// may save workouts (`.workoutType()`), which `authorizationStatus(for:)`
/// does report. The row reads green "on" only when that write grant is real.
@Observable @MainActor
final class HealthSyncCoordinator {
    static let shared = HealthSyncCoordinator()

    /// Mirrors `HealthSyncSettings.isEnabled` for the Settings toggle.
    private(set) var isEnabled: Bool
    /// The visible half of authorization: whether PlusPlus may write
    /// workouts to Health. `.notDetermined` until the first ask.
    private(set) var writeStatus: HKAuthorizationStatus = .notDetermined

    /// Health data on this device at all (false on iPad and under UI test).
    var isAvailable: Bool { HealthAccess.isAvailable }

    private init() {
        isEnabled = HealthSyncSettings.isEnabled
        refreshStatus()
    }

    /// Re-read the OS write-authorization status. Call on appear and after
    /// the system sheet resolves — the status only moves through the sheet,
    /// which this object doesn't own.
    func refreshStatus() {
        guard HealthAccess.isAvailable else { writeStatus = .notDetermined; return }
        writeStatus = HealthAccess.store.authorizationStatus(for: .workoutType())
    }

    /// Turn the integration on and ask for access. Enabling is intent; the
    /// system sheet decides the grant. Re-asking once decided is a silent
    /// no-op, so this is safe to use as the "Connect" affordance too.
    func enable() {
        HealthSyncSettings.isEnabled = true
        isEnabled = true
        HealthAccess.requestEverything { [weak self] in
            self?.refreshStatus()
        }
    }

    /// Turn the integration off: PlusPlus stops writing workouts and reading
    /// heart rate (the reads/writes all guard on `HealthSyncSettings`). It
    /// can't revoke the system grant — that lives in iOS Settings — so the
    /// tray points a user there when they want the OS to forget.
    func disable() {
        HealthSyncSettings.isEnabled = false
        isEnabled = false
    }
}

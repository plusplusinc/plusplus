import Foundation
import UserNotifications

/// Content and identity for the "rest over" notification — pure, so the
/// strings are unit-testable without UserNotifications.
enum RestNotification {
    /// One rest at a time; scheduling always replaces the previous request.
    static let identifier = "rest-end"

    static let title = "Rest over"

    static func body(exerciseName: String, setNumber: Int) -> String {
        "Set \(setNumber) — \(exerciseName)"
    }
}

/// The duration auto-timer's backgrounded-expiry notification (v2, #66).
/// Same pattern as rest: always armed, foreground-suppressed, stable
/// identifier so each timer replaces the last.
enum TimerNotification {
    static let identifier = "duration-end"

    static let title = "Time"

    static func body(exerciseName: String) -> String {
        "\(exerciseName) — set logged"
    }
}

/// Fires a local notification when the rest countdown expires while the
/// app is backgrounded or the phone is locked — the common case at the
/// gym. In the foreground the ticking RestView is already on screen, so
/// the delegate suppresses presentation entirely.
@MainActor
final class RestNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestNotifier()

    /// UI tests never see the permission dialog (it would eat the first
    /// tap of every run); the in-memory-store flag doubles as the signal.
    private let disabled = CommandLine.arguments.contains("--uitest-reset")

    private var hasRequestedAuthorization = false

    /// Call once at app start so foreground suppression is in place
    /// before any notification can fire.
    func activate() {
        guard !disabled else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asked at first routine start — the moment the permission makes
    /// sense to a user — not at app launch.
    func requestAuthorizationIfNeeded() {
        guard !disabled, !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleRestEnd(at endDate: Date, exerciseName: String, setNumber: Int) {
        guard !disabled else { return }
        cancelPending()

        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = RestNotification.title
        content.body = RestNotification.body(exerciseName: exerciseName, setNumber: setNumber)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: RestNotification.identifier, content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Skip, +15 s (before rescheduling), finish, discard, and natural
    /// expiry all funnel through here.
    func cancelPending() {
        guard !disabled else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [RestNotification.identifier, TimerNotification.identifier])
    }

    /// Arms the duration auto-timer's expiry notification; pause/reset/
    /// complete cancel or re-arm it.
    func scheduleTimerEnd(at endDate: Date, exerciseName: String) {
        guard !disabled else { return }
        cancelPending()

        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = TimerNotification.title
        content.body = TimerNotification.body(exerciseName: exerciseName)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: TimerNotification.identifier, content: content, trigger: trigger)
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [] // foreground: the rest screen is visible; a banner is noise
    }
}

import Foundation
import UserNotifications

/// Watch-local "rest over" notification (#6 bug hunt A3): the in-app
/// TimelineView haptic dies the moment the wrist drops and the app
/// suspends (no HKWorkoutSession in v1 — Health is deferred), so a
/// local notification carries the signal. Mirrors the phone's
/// RestNotifier shape: one stable identifier so each rest replaces the
/// last; cancelled on skip, natural expiry (while frontmost), and
/// session end.
enum WatchRestNotifier {
    private static let identifier = "watch-rest-over"
    private static var authorizationRequested = false

    static func schedule(at date: Date, exerciseName: String) {
        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Next: \(exerciseName)"
        content.sound = .default

        let seconds = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

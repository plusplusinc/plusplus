import Foundation

/// Device-local configuration for calendar sync (#333). Like the active
/// equipment-library pointer, this is per-device state and NOT part of
/// the interchange: which calendar the app created, and what it wrote,
/// only makes sense on the phone that holds the calendar account.
///
/// The `managedEvents` map is what makes the reconcile safe: it records
/// exactly the events PlusPlus created (keyed by routine name, #32) with
/// a fingerprint of their content, so the diff can add, update, and
/// remove without ever guessing at a user's own events. The dedicated
/// "++ Workouts" calendar is the bulk-delete lever on top of it.
enum CalendarSyncSettings {
    static let defaultHour = 7
    static let defaultMinute = 0
    static let calendarTitle = "++ Workouts"

    /// One event PlusPlus created and manages.
    struct ManagedEvent: Codable, Equatable {
        var eventIdentifier: String
        var fingerprint: String
    }

    private enum Key {
        static let enabled = "calendar.sync.enabled"
        static let hour = "calendar.sync.hour"
        static let minute = "calendar.sync.minute"
        static let calendarID = "calendar.sync.calendarIdentifier"
        static let managed = "calendar.sync.managedEvents"
    }

    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// Preferred start hour (0…23); defaults to 07:00 until the user
    /// picks a time. `object(forKey:)` distinguishes "unset" from a
    /// legitimately-stored 0.
    static var hour: Int {
        get { defaults.object(forKey: Key.hour) as? Int ?? defaultHour }
        set { defaults.set(newValue, forKey: Key.hour) }
    }

    static var minute: Int {
        get { defaults.object(forKey: Key.minute) as? Int ?? defaultMinute }
        set { defaults.set(newValue, forKey: Key.minute) }
    }

    /// The `EKCalendar.calendarIdentifier` of our "++ Workouts" calendar,
    /// nil until it's created (or after it's removed).
    static var calendarIdentifier: String? {
        get { defaults.string(forKey: Key.calendarID) }
        set { defaults.set(newValue, forKey: Key.calendarID) }
    }

    /// Routine name → the event we created for it.
    static var managedEvents: [String: ManagedEvent] {
        get {
            guard let data = defaults.data(forKey: Key.managed),
                  let decoded = try? JSONDecoder().decode([String: ManagedEvent].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.managed)
        }
    }

    /// Everything the feature persists, cleared when sync is turned off.
    static func clear() {
        defaults.removeObject(forKey: Key.enabled)
        defaults.removeObject(forKey: Key.calendarID)
        defaults.removeObject(forKey: Key.managed)
    }
}

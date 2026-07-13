import Foundation

/// Device-local on/off intent for the Apple Health integration. Like the
/// calendar and active-equipment-library pointers, this is per-device state
/// and NOT part of the interchange: what a phone syncs to Health only makes
/// sense on the phone that holds the Health database.
///
/// Health has always been a bonus the app used opportunistically whenever
/// the OS granted it (the HealthRecorder rule), so the intent defaults ON.
/// This is the switch that lets a user turn it OFF — which stops PlusPlus
/// both writing finished workouts and reading heart rate. It cannot revoke
/// the *system* authorization (only iOS Settings can), so a user who wants
/// the OS to forget what it granted is pointed there.
enum HealthSyncSettings {
    private enum Key {
        static let enabled = "health.sync.enabled"
    }

    private static var defaults: UserDefaults { .standard }

    /// Defaults TRUE. `object(forKey:)` distinguishes "never set" (→ on, the
    /// historical opportunistic behavior) from a stored `false` (the user
    /// turned it off).
    static var isEnabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }
}

import Foundation

/// Device-local opt-in for the phone running its OWN `HKWorkoutSession`
/// while a workout is on screen, rather than writing the workout to Health
/// after the fact (`HealthRecorder`).
///
/// **Defaults OFF, and that is the design, not caution.** The live path
/// changes who owns the save, who measures energy, and which sensor stream
/// the heart-rate capsule reads — three things that can only be judged on a
/// real device with a real wrist. Off means the app behaves exactly as it
/// has since #90: a retrospective write at finish, an anchored query for
/// live heart rate. On means the phone becomes the recorder. Flipping the
/// switch back is the whole rollback, with no data shape to unwind.
///
/// Not part of the interchange, for the same reason `HealthSyncSettings`
/// isn't: what a phone records only makes sense on the phone holding the
/// Health database.
enum LiveWorkoutSettings {
    /// Public so the Settings toggle can bind it with `@AppStorage` —
    /// a plain `Binding` over `UserDefaults` writes but never redraws.
    static let key = "health.liveWorkout.enabled"

    private static var defaults: UserDefaults { .standard }

    /// Defaults FALSE — unlike `HealthSyncSettings`, which defaults on
    /// because it describes the behavior the app already had.
    static var isEnabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }

    /// Whether the live path may run at all right now: the user asked for
    /// it, Health is usable, and the Health integration itself is on.
    /// Every entry point asks this, so one false makes the whole feature
    /// inert.
    static var isActive: Bool {
        isEnabled && HealthAccess.isAvailable && HealthSyncSettings.isEnabled
    }
}

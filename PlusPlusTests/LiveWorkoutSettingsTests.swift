import Foundation
import Testing
@testable import PlusPlus

/// The reversibility contract for the phone's own workout session.
///
/// The runtime behavior cannot be tested — it needs HealthKit, sensors and
/// a wrist. What CAN be pinned is the property the whole design rests on:
/// **off unless asked for, and one switch is the entire rollback.** If this
/// suite goes red, the live path has started running for people who never
/// opted into it.
@Suite("Live workout recording — off unless asked for", .serialized)
struct LiveWorkoutSettingsTests {
    /// ⚠️ Reads process-global `UserDefaults`, so the suite is `.serialized`
    /// and every test restores what it found. A leaked `true` here would
    /// arm the live path for every later test in the process.
    private func withRestoredDefault(_ body: () -> Void) {
        let original = UserDefaults.standard.object(forKey: LiveWorkoutSettings.key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: LiveWorkoutSettings.key)
            } else {
                UserDefaults.standard.removeObject(forKey: LiveWorkoutSettings.key)
            }
        }
        body()
    }

    @Test("An install that has never heard of this records the old way")
    func defaultsOff() {
        withRestoredDefault {
            UserDefaults.standard.removeObject(forKey: LiveWorkoutSettings.key)
            #expect(!LiveWorkoutSettings.isEnabled)
            // And the composite gate agrees, whatever else is true: a
            // feature nobody asked for cannot be active.
            #expect(!LiveWorkoutSettings.isActive)
        }
    }

    @Test("The switch is the whole rollback, both ways")
    func togglesBothWays() {
        withRestoredDefault {
            LiveWorkoutSettings.isEnabled = true
            #expect(LiveWorkoutSettings.isEnabled)
            LiveWorkoutSettings.isEnabled = false
            #expect(!LiveWorkoutSettings.isEnabled)
            #expect(!LiveWorkoutSettings.isActive)
        }
    }

    @Test("Turning Health off turns this off with it")
    func healthOffWinsOverTheOptIn() {
        withRestoredDefault {
            let health = HealthSyncSettings.isEnabled
            defer { HealthSyncSettings.isEnabled = health }

            LiveWorkoutSettings.isEnabled = true
            HealthSyncSettings.isEnabled = false
            // The user turned the whole integration off. A live session
            // would still be recording them to Health, which is the one
            // thing that switch promises to stop.
            #expect(!LiveWorkoutSettings.isActive)
        }
    }
}

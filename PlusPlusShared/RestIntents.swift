import AppIntents
import Foundation

/// Island / Lock Screen rest controls (#157). These compile into BOTH
/// the app and the widget extension: the extension needs the types to
/// place `Button(intent:)` in the Live Activity, and the system executes
/// `LiveActivityIntent` in the APP's process — so posting on
/// NotificationCenter reaches the live rest view, the same code path as
/// the on-screen stepper and Skip. If no session view is alive (the app
/// was terminated under the activity), the post lands nowhere and the
/// island keeps counting — display-only, exactly the pre-#157 behavior.

extension Notification.Name {
    /// Posted with a `RestAdjustment` rawValue as `object`.
    static let plusplusAdjustRest = Notification.Name("plusplusAdjustRest")
}

enum RestAdjustment: String {
    /// The step both surfaces move by. 15 s, not 30 (Dave, 2026-07-27):
    /// rest is now something you dial in either direction, and 30 was
    /// too coarse to land on the length you actually wanted.
    static let stepSeconds = 15

    case add
    case subtract
    case skip
}

struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add Rest Time"
    static let description = IntentDescription("Adds 15 seconds to the current rest.")
    /// Island-only control, not a Shortcuts verb.
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .plusplusAdjustRest, object: RestAdjustment.add.rawValue
        )
        return .result()
    }
}

struct ReduceRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Reduce Rest Time"
    static let description = IntentDescription("Takes 15 seconds off the current rest.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .plusplusAdjustRest, object: RestAdjustment.subtract.rawValue
        )
        return .result()
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Rest"
    static let description = IntentDescription("Ends the current rest.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .plusplusAdjustRest, object: RestAdjustment.skip.rawValue
        )
        return .result()
    }
}

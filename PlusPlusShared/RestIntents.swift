import AppIntents
import Foundation

/// Island / Lock Screen rest controls (#157). These compile into BOTH
/// the app and the widget extension: the extension needs the types to
/// place `Button(intent:)` in the Live Activity, and the system executes
/// `LiveActivityIntent` in the APP's process — so posting on
/// NotificationCenter reaches the live rest view, the same code path as
/// the on-screen +15s/Skip buttons. If no session view is alive (the app
/// was terminated under the activity), the post lands nowhere and the
/// island keeps counting — display-only, exactly the pre-#157 behavior.

extension Notification.Name {
    /// Posted with a `RestAdjustment` rawValue as `object`.
    static let plusplusAdjustRest = Notification.Name("plusplusAdjustRest")
}

enum RestAdjustment: String {
    case addFifteen
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
            name: .plusplusAdjustRest, object: RestAdjustment.addFifteen.rawValue
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

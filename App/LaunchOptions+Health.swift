#if DEBUG
import Foundation
import Health
import Synchronization
import WorkoutStore

extension LaunchOptions {
    /// Apple Health for this launch. `-seedHealth notAsked|on|off` gives a fake that starts
    /// there, whose ask turns it on, for screenshots of Settings in each state. Otherwise a launch
    /// from an empty store, as the UI tests start, gets none: the simulator's Health permission
    /// outlives a run, and a test would depend on the one before it.
    static var healthClient: HealthClient? {
        let seeded: HealthAccess? = switch UserDefaults.standard.string(forKey: "seedHealth") {
        case "notAsked": .notAsked
        case "on": .on
        case "off": .off
        default: nil
        }
        if let seeded {
            return FakeHealth(seeded).client
        }
        return resetsStore ? .unavailable : nil
    }
}

/// A Health that answers as seeded and removes and saves nothing, handing back a new id for each
/// save.
private final class FakeHealth: Sendable {
    private let access: Mutex<HealthAccess>

    init(_ access: HealthAccess) {
        self.access = Mutex(access)
    }

    var client: HealthClient {
        HealthClient(
            access: { self.access.withLock { $0 } },
            ask: {
                self.access.withLock { access in
                    if access == .notAsked {
                        access = .on
                    }
                }
            },
            remove: { _, _ in },
            save: { _ in UUID() },
        )
    }
}
#endif

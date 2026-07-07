import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Owns the rest-countdown Live Activity (#147). Driven from
/// RestNotifier's lifecycle moments — the same places the "rest over"
/// notification arms and disarms — so the island and the notification
/// can never disagree about whether a rest is running.
@MainActor
final class RestActivityController {
    static let shared = RestActivityController()

    /// Same test gate as RestNotifier: no system surfaces under UI tests.
    private let disabled = CommandLine.arguments.contains("--uitest-reset")

    private var routineName: String = ""

    /// The active session's routine, for the activity's fixed context.
    /// Set at workout start; cheap enough to set redundantly.
    func beginSession(routineName: String) {
        self.routineName = routineName
    }

    func restStarted(endDate: Date, exerciseName: String, setNumber: Int) {
        #if canImport(ActivityKit)
        guard !disabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestActivityAttributes.ContentState(
            endDate: endDate,
            exerciseName: exerciseName,
            setNumber: setNumber
        )
        Task {
            if let activity = Activity<RestActivityAttributes>.activities.first {
                await activity.update(ActivityContent(state: state, staleDate: endDate))
            } else {
                let attributes = RestActivityAttributes(routineName: routineName)
                _ = try? Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: endDate)
                )
            }
        }
        #endif
    }

    /// Skip, finish, discard, and natural expiry all end the island.
    func restEnded() {
        #if canImport(ActivityKit)
        guard !disabled else { return }
        Task {
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}

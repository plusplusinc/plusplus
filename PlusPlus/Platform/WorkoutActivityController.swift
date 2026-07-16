import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Owns the whole-session workout Live Activity (#322). One activity
/// starts when the session begins and ends when it finishes/discards; in
/// between it rides in `.working` (current exercise + set progress +
/// count-up elapsed) and swaps to `.resting` (countdown + controls)
/// between sets. Driven from ActiveSessionView's lifecycle so the island,
/// the on-screen state, and the watch mirror can't disagree.
///
/// Date-based throughout (elapsed from `sessionStart`, countdown to
/// `restEnd`) so the island renders both timers natively without the app
/// awake. Because ONE activity spans the session, rest transitions are
/// in-place `update`s — the activity is never torn down mid-session, so
/// the island's own +30s can't destroy it (the pre-#322 rest-only bug).
@MainActor
final class WorkoutActivityController {
    static let shared = WorkoutActivityController()

    /// No system surfaces under UI tests (same gate as the old notifier).
    private let disabled = CommandLine.arguments.contains("--uitest-reset")

    /// Held so rest/working updates can restamp the count-up elapsed base.
    private var sessionStart = Date()

    func begin(routineName: String, exerciseName: String, setNumber: Int, setsCompleted: Int, totalSets: Int, startedAt: Date) {
        #if canImport(ActivityKit)
        guard !disabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        sessionStart = startedAt
        endAll() // never stack two workout activities
        let state = WorkoutActivityAttributes.ContentState(
            phase: .working,
            exerciseName: exerciseName,
            setNumber: setNumber,
            setsCompleted: setsCompleted,
            totalSets: totalSets,
            sessionStart: startedAt,
            restEnd: nil
        )
        _ = try? Activity.request(
            attributes: WorkoutActivityAttributes(routineName: routineName),
            content: ActivityContent(state: state, staleDate: nil)
        )
        #endif
    }

    func working(exerciseName: String, setNumber: Int, setsCompleted: Int, totalSets: Int) {
        #if canImport(ActivityKit)
        guard !disabled else { return }
        update(WorkoutActivityAttributes.ContentState(
            phase: .working,
            exerciseName: exerciseName,
            setNumber: setNumber,
            setsCompleted: setsCompleted,
            totalSets: totalSets,
            sessionStart: sessionStart,
            restEnd: nil
        ), staleDate: nil)
        #endif
    }

    func resting(upNextExercise: String, upNextSet: Int, setsCompleted: Int, totalSets: Int, restEnd: Date, isTransition: Bool = false) {
        #if canImport(ActivityKit)
        guard !disabled else { return }
        update(WorkoutActivityAttributes.ContentState(
            phase: .resting,
            exerciseName: upNextExercise,
            setNumber: upNextSet,
            setsCompleted: setsCompleted,
            totalSets: totalSets,
            sessionStart: sessionStart,
            restEnd: restEnd,
            isTransition: isTransition
        ), staleDate: restEnd)
        #endif
    }

    /// Finish, discard, and leaving the session all end the activity.
    func end() {
        #if canImport(ActivityKit)
        guard !disabled else { return }
        endAll()
        #endif
    }

    #if canImport(ActivityKit)
    private func update(_ state: WorkoutActivityAttributes.ContentState, staleDate: Date?) {
        Task {
            guard let activity = Activity<WorkoutActivityAttributes>.activities.first else { return }
            await activity.update(ActivityContent(state: state, staleDate: staleDate))
        }
    }

    private func endAll() {
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    #endif
}

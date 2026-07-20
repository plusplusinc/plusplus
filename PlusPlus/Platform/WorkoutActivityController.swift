import Foundation
import OSLog
#if canImport(ActivityKit)
import ActivityKit
#endif

private let activityLog = Logger(subsystem: "com.davidcole.plusplus", category: "live-activity")

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
        guard !disabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Live Activities disabled for PlusPlus in Settings — nothing will
            // show on the island/lock screen. Logged so a silent no-op is
            // visible in a device sysdiagnose (the pre-fix invisibility, #419).
            activityLog.notice("workout Live Activity not started: activities disabled in Settings")
            return
        }
        sessionStart = startedAt
        // Snapshot any pre-existing activities BEFORE requesting the new one, so
        // the teardown ends only stale activities and can never reap the one we
        // just created. `endAll()` inside a Task raced `Activity.request` here —
        // the new activity landed in `.activities` before the loop ran and was
        // immediately dismissed, suppressing the island/lock screen all session
        // (#419). Ending a captured value array is race-free by construction.
        let stale = Activity<WorkoutActivityAttributes>.activities
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
        end(stale) // never stack two workout activities
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
        end(Activity<WorkoutActivityAttributes>.activities)
    }

    /// End a captured set of activities. Callers snapshot `.activities` first so
    /// an activity created after the snapshot is never dismissed by this loop.
    private func end(_ activities: [Activity<WorkoutActivityAttributes>]) {
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    #endif
}

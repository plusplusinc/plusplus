import Foundation
import HealthKit

/// Writes finished phone-logged sessions to Health as workouts (#90).
/// Watch-logged sessions never pass through here — the wrist records its
/// own live workout (WatchWorkoutController), and a second write would
/// double-count the training.
///
/// Health is a bonus, never a gate: unavailable, undecided, or denied all
/// mean "skip silently". Disabled under --uitest-reset so the permission
/// sheet can't eat a smoke test's tap (same rule as RestNotifier).
enum HealthRecorder {
    private static var store: HKHealthStore { HealthAccess.store }

    /// Call at the moment a session transitions to finished, on the main
    /// actor — model fields are read here and captured as plain values
    /// before any HealthKit callback hops threads.
    static func record(_ session: WorkoutSession) {
        guard HealthAccess.isAvailable,
              let endedAt = session.endedAt,
              !session.completedSetLogs.isEmpty
        else { return }
        let startedAt = session.startedAt
        // The prompt lands on the "Workout Complete" screen the first
        // time — auth requested in context, remembered system-wide after.
        store.requestAuthorization(toShare: [.workoutType()], read: []) { success, _ in
            guard success else { return }
            save(start: startedAt, end: max(endedAt, startedAt.addingTimeInterval(1)))
        }
    }

    private static func save(start: Date, end: Date) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        builder.beginCollection(withStart: start) { success, _ in
            guard success else { return }
            builder.endCollection(withEnd: end) { success, _ in
                guard success else { return }
                builder.finishWorkout { _, _ in }
            }
        }
    }
}

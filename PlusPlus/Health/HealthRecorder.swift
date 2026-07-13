import Foundation
import HealthKit
import CoreLocation

/// Writes finished phone-logged sessions to Health as workouts (#90).
/// Watch-logged sessions never pass through here — the wrist records its
/// own live workout (WatchWorkoutController), and a second write would
/// double-count the training.
///
/// Health is a bonus, never a gate: unavailable, undecided, or denied all
/// mean "skip silently". Disabled under --uitest-reset so the permission
/// sheet can't eat a smoke test's tap (same gate as the workout Live
/// Activity controller).
///
/// **Activity type + route (#348):** an outdoor run logged on the phone is
/// saved as a `.running`/`.outdoor` workout carrying its GPS route (so it
/// shows a map in Health/Fitness), driven off the fixes the
/// `RunLocationMonitor` collected. Everything else stays
/// `.traditionalStrengthTraining`/`.indoor`. We deliberately do NOT attach
/// heart-rate samples (they already exist in Health from the watch/strap;
/// re-adding them would double-count) or an energy figure (the phone
/// measures none, and fabricating `activeEnergy` is wrong) — those belong to
/// a live builder like the watch's, not this after-the-fact write.
enum HealthRecorder {
    private static var store: HKHealthStore { HealthAccess.store }

    /// Call at the moment a session transitions to finished, on the main
    /// actor — model fields are read here and captured as plain values
    /// before any HealthKit callback hops threads. `route` is the outdoor
    /// run's GPS fixes (empty for an indoor/strength session); a non-empty
    /// route both classifies the workout as an outdoor run and gets saved.
    static func record(_ session: WorkoutSession, route: [CLLocation] = []) {
        guard HealthAccess.isAvailable,
              HealthSyncSettings.isEnabled,
              let endedAt = session.endedAt,
              !session.completedSetLogs.isEmpty
        else { return }
        // The workout-clock anchor, not the session's creation: an
        // ad-hoc session's Health window starts when the first exercise
        // did, not while it was being assembled.
        let startedAt = session.effectiveStart
        let outdoor = !route.isEmpty
        // Saving a route needs the workout-route series type in the share
        // set alongside the workout itself.
        var share: Set<HKSampleType> = [.workoutType()]
        if outdoor { share.insert(HKSeriesType.workoutRoute()) }
        // The prompt lands on the "Workout Complete" screen the first
        // time — auth requested in context, remembered system-wide after.
        store.requestAuthorization(toShare: share, read: []) { success, _ in
            guard success else { return }
            save(start: startedAt, end: max(endedAt, startedAt.addingTimeInterval(1)),
                 outdoor: outdoor, route: route)
        }
    }

    private static func save(start: Date, end: Date, outdoor: Bool, route: [CLLocation]) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = outdoor ? .running : .traditionalStrengthTraining
        configuration.locationType = outdoor ? .outdoor : .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        // The route builder is spun off the workout builder and fed the
        // fixes during collection; the route is associated after the
        // workout is saved (Apple's documented order). nil when there's no
        // route, so a strength write is byte-for-byte the old path.
        let routeBuilder = route.isEmpty
            ? nil
            : builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
        builder.beginCollection(withStart: start) { success, _ in
            guard success else { return }
            // End the workout, save it, then attach the finished route to
            // the saved sample. Every step is guarded: a failure anywhere
            // leaves the workout intact (or absent) and just drops the
            // route — Health is a bonus, never a gate.
            let endAndFinish = {
                builder.endCollection(withEnd: end) { success, _ in
                    guard success else { return }
                    builder.finishWorkout { workout, _ in
                        // Both nil = saved but the sample is unavailable
                        // (device locked); no workout to bind the route to.
                        guard let workout, let routeBuilder else { return }
                        routeBuilder.finishRoute(with: workout, metadata: nil) { _, _ in }
                    }
                }
            }
            if let routeBuilder {
                routeBuilder.insertRouteData(route) { _, _ in endAndFinish() }
            } else {
                endAndFinish()
            }
        }
    }
}

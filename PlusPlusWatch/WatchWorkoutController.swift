import Foundation
import HealthKit

/// HealthKit runtime for wrist execution (#90): an HKWorkoutSession keeps
/// the app running with the wrist down (so the rest haptic fires directly
/// and the notification stays a suspension backstop), streams heart rate
/// and energy into the workout via the live builder, and earns Activity
/// ring credit when the session saves.
///
/// Health is a bonus, never a gate: if HealthKit is unavailable or the
/// user declines, every method quietly no-ops and the run view behaves
/// exactly as it did before #90.
final class WatchWorkoutController {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Request authorization (first run only — the system remembers) and
    /// begin a workout session. Idempotent; failures leave us inert.
    func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        // Share covers everything the live builder saves with the workout;
        // read lets the data source collect from the sensors.
        let share: Set<HKSampleType> = [
            .workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        // `success` means the request was processed, not that anything was
        // granted (HealthKit never reveals denial). Begin regardless: with
        // denied share auth the builder's saves fail and we ignore them.
        store.requestAuthorization(toShare: share, read: read) { [weak self] success, _ in
            guard success else { return }
            DispatchQueue.main.async { self?.begin() }
        }
    }

    private func begin() {
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
            self.session = session
            self.builder = builder
        } catch {
            // No session — the run view still works, minus runtime + HR.
        }
    }

    /// End collection and save the workout to Health. Idempotent.
    func finish() {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in
            builder.finishWorkout { _, _ in }
        }
    }

    /// Throw the session away — the user looked at a routine and left
    /// without logging anything. Idempotent.
    func discard() {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        builder.discardWorkout()
    }
}

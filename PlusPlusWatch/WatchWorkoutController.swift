import Foundation
import HealthKit
import Observation

/// HealthKit runtime for wrist execution (#90): an HKWorkoutSession keeps
/// the app running with the wrist down (so the rest haptic fires directly
/// and the notification stays a suspension backstop), streams heart rate
/// and energy into the workout via the live builder, and earns Activity
/// ring credit when the session saves. The builder's statistics surface
/// as live/average/max bpm — the run view renders the live number and
/// the finish ships the summary home in the result payload.
///
/// Health is a bonus, never a gate: if HealthKit is unavailable or the
/// user declines, every method quietly no-ops and the run view behaves
/// exactly as it did before #90.
@Observable
final class WatchWorkoutController: NSObject, HKLiveWorkoutBuilderDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Heart rate from the live builder, published on the main queue.
    /// nil until the first sample (and forever, when Health said no).
    /// The summary values survive `finish()` — the run view reads them
    /// while composing the result payload.
    private(set) var latestBPM: Int?
    private(set) var averageBPM: Int?
    private(set) var maxBPM: Int?

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
            builder.delegate = self
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
            self.session = session
            self.builder = builder
        } catch {
            // No session — the run view still works, minus runtime + HR.
        }
    }

    /// End collection and save the workout to Health. Idempotent. The
    /// bpm summary stays readable afterward.
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

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRate),
              let statistics = workoutBuilder.statistics(for: heartRate) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let latest = statistics.mostRecentQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
        let average = statistics.averageQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
        let peak = statistics.maximumQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let latest { self.latestBPM = latest }
            if let average { self.averageBPM = average }
            if let peak { self.maxBPM = peak }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

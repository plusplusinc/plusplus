import Foundation
import CoreLocation
import HealthKit
import Observation
import PlusPlusKit

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

    /// Live pace during an OUTDOOR run, from the builder's fused
    /// distanceWalkingRunning fed into a Kit pace meter. nil for indoor
    /// sessions (no distance collected) and until GPS locks. Read through
    /// `livePaceSeconds`, which expires a stale value.
    private(set) var currentPaceSeconds: Double?
    private(set) var latestPaceAt: Date?

    /// How long a pace reading stays "live" without a new distance sample —
    /// when you stop, HealthKit stops delivering distance, so the last
    /// pace must age out rather than freeze on screen.
    private static let paceFreshWindow: TimeInterval = 20

    /// The pace to show: the latest reading while it's fresh, else nil (so
    /// standing still clears it, matching the phone's staleness gate).
    var livePaceSeconds: Double? {
        guard let currentPaceSeconds, let latestPaceAt,
              Date().timeIntervalSince(latestPaceAt) < Self.paceFreshWindow else { return nil }
        return currentPaceSeconds
    }

    /// Location authorization is required for an outdoor session's GPS
    /// distance — we don't consume fixes ourselves, the workout does.
    private let locationManager = CLLocationManager()
    private var paceMeter: LivePaceMeter?
    private var sessionStart: Date?

    /// Request authorization (first run only — the system remembers) and
    /// begin a workout session. Idempotent; failures leave us inert. On an
    /// outdoor run the session runs as `.running`/`.outdoor`, collects GPS
    /// distance, and surfaces live pace in the run's `unit`.
    func start(outdoorRun: Bool = false, unit: DistanceUnit = .miles) {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        // Share covers everything the live builder saves with the workout;
        // read lets the data source collect from the sensors. Distance is
        // an outdoor-only ask.
        var share: Set<HKSampleType> = [
            .workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        var read: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        if outdoorRun {
            share.insert(HKQuantityType(.distanceWalkingRunning))
            read.insert(HKQuantityType(.distanceWalkingRunning))
            paceMeter = LivePaceMeter(unit: unit)
            // GPS distance needs location authorization; the workout
            // consumes the fixes, we just hold the grant.
            locationManager.requestWhenInUseAuthorization()
        }
        // `success` means the request was processed, not that anything was
        // granted (HealthKit never reveals denial). Begin regardless: with
        // denied share auth the builder's saves fail and we ignore them.
        store.requestAuthorization(toShare: share, read: read) { [weak self] success, _ in
            guard success else { return }
            DispatchQueue.main.async { self?.begin(outdoorRun: outdoorRun) }
        }
    }

    private func begin(outdoorRun: Bool) {
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        // One session is one activity type — the caller only asks for
        // outdoor when the whole routine is a run (PlanRoutine.isOutdoorRun).
        configuration.activityType = outdoorRun ? .running : .traditionalStrengthTraining
        configuration.locationType = outdoorRun ? .outdoor : .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            let now = Date()
            sessionStart = now
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { _, _ in }
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
        if collectedTypes.contains(heartRate), let statistics = workoutBuilder.statistics(for: heartRate) {
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

        // Outdoor run: feed HealthKit's fused cumulative distance into the
        // pace meter (better than raw CLLocation — it blends GPS + motion).
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        if paceMeter != nil, collectedTypes.contains(distanceType),
           let statistics = workoutBuilder.statistics(for: distanceType),
           let meters = statistics.sumQuantity()?.doubleValue(for: .meter()),
           let start = sessionStart {
            paceMeter?.ingest(at: Date().timeIntervalSince(start), cumulativeMeters: meters)
            let pace = paceMeter?.currentPaceSeconds
            DispatchQueue.main.async { [weak self] in
                self?.currentPaceSeconds = pace
                self?.latestPaceAt = pace != nil ? Date() : nil
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

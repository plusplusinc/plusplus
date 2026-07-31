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
    /// Readings collected since the current STEP began. The builder's own
    /// statistics are session-wide, which is the wrong window for a set:
    /// a 4 × 500 m piece wants four numbers, and an hour of lifting
    /// averaged whole says almost nothing. Reset by `beginStep()` at each
    /// log, exactly like `distanceAtStepStart` on the view side.
    private var stepBPMs: [Int] = []

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

    /// Cumulative MEASURED distance so far, in the run's own unit. nil
    /// indoors, where nothing is collected. The run view subtracts the
    /// reading it took at a step's start to get that step's own distance,
    /// which is what turns a wrist-logged interval into real splits
    /// instead of a copy of its prescription.
    private(set) var totalDistance: Double?
    /// The unit `totalDistance` is denominated in — held so callers don't
    /// have to remember what they started the session with.
    private(set) var distanceUnit: DistanceUnit = .miles

    /// Location authorization is required for an outdoor session's GPS
    /// distance — we don't consume fixes ourselves, the workout does.
    private let locationManager = CLLocationManager()
    private var paceMeter: LivePaceMeter?
    /// Which distance quantity this session accrues — cycling distance on
    /// a ride, walking/running on a run. nil when nothing is collected.
    private var collectedDistanceType: HKQuantityType?
    private var sessionStart: Date?

    /// Request authorization (first run only — the system remembers) and
    /// begin a workout session. Idempotent; failures leave us inert.
    ///
    /// The session is configured from the plan's own `SessionModality` —
    /// the same Kit map the phone's recorder uses, so a ride logged here
    /// and a ride logged there file identically. It used to be an
    /// `outdoorRun` Bool, which could only ever say "running/outdoor" or
    /// "strength/indoor".
    func start(modality: SessionModality = .empty, unit: DistanceUnit = .miles) {
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
        // ⚠️ The quantity follows the SPORT: a ride accrues
        // `.distanceCycling`, not walking/running distance. Outdoor used
        // to mean "a run" in practice, so one hardcoded type sufficed.
        if modality.isOutdoor, let distanceType = modality.healthDistanceType {
            share.insert(distanceType)
            read.insert(distanceType)
            collectedDistanceType = distanceType
            paceMeter = LivePaceMeter(unit: unit)
            distanceUnit = unit
            // GPS distance needs location authorization; the workout
            // consumes the fixes, we just hold the grant.
            locationManager.requestWhenInUseAuthorization()
        }
        // `success` means the request was processed, not that anything was
        // granted (HealthKit never reveals denial). Begin regardless: with
        // denied share auth the builder's saves fail and we ignore them.
        store.requestAuthorization(toShare: share, read: read) { [weak self] success, _ in
            guard success else { return }
            DispatchQueue.main.async { self?.begin(modality: modality) }
        }
    }

    private func begin(modality: SessionModality) {
        guard session == nil else { return }
        // One session is one activity type, so a mixed plan resolves to
        // cross-training rather than claiming to be all of one sport.
        let configuration = modality.healthConfiguration
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            session.delegate = self
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

    /// Start a fresh per-step heart-rate window. Called as each step is
    /// logged, so the NEXT step measures only itself.
    func beginStep() {
        stepBPMs.removeAll()
    }

    /// This step's average, or nil when nothing was read — never a zero,
    /// and never the session's number standing in for the set's.
    var stepAverageBPM: Int? {
        guard !stepBPMs.isEmpty else { return nil }
        return Int((Double(stepBPMs.reduce(0, +)) / Double(stepBPMs.count)).rounded())
    }

    var stepMaxBPM: Int? { stepBPMs.max() }

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
                if let latest {
                    self.latestBPM = latest
                    self.stepBPMs.append(latest)
                }
                if let average { self.averageBPM = average }
                if let peak { self.maxBPM = peak }
            }
        }

        // Outdoor run: feed HealthKit's fused cumulative distance into the
        // pace meter (better than raw CLLocation — it blends GPS + motion).
        guard let distanceType = collectedDistanceType else { return }
        if paceMeter != nil, collectedTypes.contains(distanceType),
           let statistics = workoutBuilder.statistics(for: distanceType),
           let meters = statistics.sumQuantity()?.doubleValue(for: .meter()),
           let start = sessionStart {
            paceMeter?.ingest(at: Date().timeIntervalSince(start), cumulativeMeters: meters)
            let pace = paceMeter?.currentPaceSeconds
            // The running total in the run's own unit, so a logged step
            // can record the distance it actually covered.
            let total = paceMeter.map { $0.unit.value(fromMeters: $0.totalMeters) }
            DispatchQueue.main.async { [weak self] in
                self?.currentPaceSeconds = pace
                self?.latestPaceAt = pace != nil ? Date() : nil
                self?.totalDistance = total
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - HKWorkoutSessionDelegate (stage 1, #510)

extension WatchWorkoutController: HKWorkoutSessionDelegate {
    /// The system can end the session under us (another workout started,
    /// resources reclaimed). Without a delegate that death was silent —
    /// HR simply stopped streaming and the screen kept its last number.
    /// Degrade honestly: drop the runtime and clear the LIVE readings so
    /// the UI stops claiming a sensor it lost; the summary values stay,
    /// they are the best truth collected.
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.builder?.discardWorkout()
            self.session = nil
            self.builder = nil
            self.latestBPM = nil
            self.currentPaceSeconds = nil
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        // Our own finish()/discard() nil the session BEFORE ending it, so
        // this guard only passes when something ELSE ended the session —
        // same honest degrade as a failure.
        guard toState == .ended || toState == .stopped else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.session = nil
            self.builder = nil
            self.latestBPM = nil
            self.currentPaceSeconds = nil
        }
    }
}

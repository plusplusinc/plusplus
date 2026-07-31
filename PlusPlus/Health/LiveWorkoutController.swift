import Foundation
import CoreLocation
import HealthKit
import Observation
import PlusPlusKit

/// The phone running its own live workout, the way the wrist always has.
///
/// **iOS 26 is the first release where an iPhone can ORIGINATE an
/// `HKWorkoutSession`** and drive a local `HKLiveWorkoutBuilder`. Before
/// it, the phone could only mirror a watch-started session, which is why
/// `HealthRecorder` writes the workout after the fact — and why three
/// things have always been slightly wrong on a phone-logged workout:
///
/// - **Energy was a fabrication question.** The retrospective write
///   deliberately records none, because the phone measured none. A live
///   session gets Apple's own estimator, so a phone-tracked ride finally
///   moves the Move ring.
/// - **Live heart rate lagged** (#418). The passive anchored query reads
///   whatever Health has, and watch→phone sample delivery is batched, so
///   the newest visible sample was routinely older than the 180 s
///   freshness gate — the capsule stayed blank all workout while the
///   finish-time statistics query found the samples had been there.
///   A locally-originated session's builder delivers what it collects.
/// - **The workout existed only at the end.** Nothing was recording while
///   it happened, so a crash mid-run left no trace.
///
/// ⚠️ **This is additive and reversible by construction.** It runs only
/// when `LiveWorkoutSettings.isActive`, which is off by default; with the
/// switch off nothing here executes and the retrospective path is
/// untouched. That matters because NONE of this can be validated without a
/// device: CI compiles it, and no test can tell you whether a real wrist
/// streams into a phone-originated session.
///
/// ⚠️ **Exactly one sensor owner per session.** The wrist starts its own
/// session when its run view appears, and two concurrent sessions make
/// HealthKit raise `anotherWorkoutSessionStarted` and kill one of them.
/// Rather than negotiate custody across devices, this degrades: any
/// session failure clears `ownsRecording`, and the caller falls back to
/// the retrospective writer it was using anyway.
@MainActor
@Observable
final class LiveWorkoutController: NSObject {
    static let shared = LiveWorkoutController()

    /// Whether a live session is recording RIGHT NOW and will save the
    /// workout itself. ⚠️ The one flag `finishSession` reads to decide
    /// whether `HealthRecorder` also writes — two writers for one workout
    /// is a duplicate in Health, which is worse than either alone.
    private(set) var ownsRecording = false

    /// Live readings from the builder's own statistics. nil until the
    /// first sample of each, and nil forever when nothing measures it.
    private(set) var latestBPM: Int?
    private(set) var averageBPM: Int?
    private(set) var maxBPM: Int?
    /// What Apple's estimator says this workout has burned so far. The
    /// phone has never had an honest number for this before.
    private(set) var activeEnergyKilocalories: Int?

    /// When the last heart-rate reading arrived, so a stalled stream ages
    /// out instead of freezing a number on screen — the same rule the
    /// anchored-query path applies, with a far shorter window because a
    /// live builder that is working delivers continuously.
    private(set) var latestBPMAt: Date?
    static let bpmFreshWindow: TimeInterval = 30

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The run's GPS fixes, handed over at `finish` and held until
    /// `.stopped` lands — the end sequence's tail runs from the session
    /// delegate, which has no way to be given anything.
    private var pendingRoute: [CLLocation] = []

    private override init() { super.init() }

    // MARK: - Lifecycle

    /// Begin recording. Idempotent, and a silent no-op whenever the
    /// feature is off, Health is unavailable, or a session is already in
    /// hand. Failure to construct the session leaves `ownsRecording`
    /// false, which is the whole fallback: the caller writes
    /// retrospectively exactly as before.
    func start(modality: SessionModality, at date: Date) {
        guard LiveWorkoutSettings.isActive, session == nil else { return }
        // ⚠️ ADOPT before creating. A session survives the app — a crash
        // or the system reclaiming the process mid-workout leaves the
        // sensors recording — and starting a second one raises
        // `anotherWorkoutSessionStarted`, which kills ours and loses the
        // first. Recovery lives here rather than at launch for the same
        // reason: this is the only moment the app actually wants a live
        // session, so a recovered one can never sit orphaned holding the
        // slot for a workout that has already been finished or discarded.
        adoptRecoveredSession { [weak self] adopted in
            guard let self, !adopted else { return }
            self.beginFresh(modality: modality, at: date)
        }
    }

    private func beginFresh(modality: SessionModality, at date: Date) {
        // Share covers everything the builder saves with the workout;
        // read lets the data source collect from the sensors. The
        // distance ask follows the SPORT — a ride accrues
        // `.distanceCycling`, and asking for walking/running distance on
        // a bike gets a number that never moves.
        var share: Set<HKSampleType> = [
            .workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        var read: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        if let distanceType = modality.healthDistanceType {
            share.insert(distanceType)
            read.insert(distanceType)
        }
        // Saving a route needs the series type in the share set, and the
        // ask happens HERE, before anyone knows whether the run will
        // produce one. An outdoor session is the only kind that can, so
        // outdoor is the gate — asking for it on an erg would be a
        // permission the workout can never use.
        if modality.isOutdoor {
            share.insert(HKSeriesType.workoutRoute())
        }
        // `success` means the request was processed, never that anything
        // was granted — HealthKit does not reveal denial. Begin either
        // way: with the share denied the builder's save fails and we have
        // already told the caller we own it, which is the one case a
        // workout goes missing from Health. Health is a bonus, never a
        // gate, and the set actuals still hold the record.
        // ⚠️ The sets go across as ARGUMENTS and the MODALITY is what the
        // callback captures. A `HKWorkoutConfiguration` is a reference
        // type HealthKit owns; `SessionModality` is a Kit value, so
        // rebuilding the configuration on the other side keeps a
        // non-Sendable object out of the escaping closure. Same shape as
        // the wrist's controller.
        HealthAccess.store.requestAuthorization(toShare: share, read: read) { success, _ in
            guard success else { return }
            Task { @MainActor [weak self] in
                self?.begin(modality: modality, at: date)
            }
        }
    }

    private func begin(modality: SessionModality, at date: Date) {
        // The authorization callback is asynchronous, so re-check both
        // gates: the user can have finished (or discarded) the workout
        // while the sheet was up.
        guard LiveWorkoutSettings.isActive, session == nil else { return }
        let configuration = modality.healthConfiguration
        do {
            let session = try HKWorkoutSession(healthStore: HealthAccess.store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: HealthAccess.store,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self
            session.startActivity(with: date)
            builder.beginCollection(withStart: date) { _, _ in }
            self.session = session
            self.builder = builder
            ownsRecording = true
        } catch {
            // An invalid configuration, or HealthKit refusing. Nothing
            // owns the recording, so the retrospective writer does.
            clear()
        }
    }

    /// Hold the session across a workout pause, so the paused minutes do
    /// not count as effort. Both are no-ops without a session.
    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// End the session and save the workout.
    ///
    /// ⚠️ **The sequence is exact and is the classic bug:**
    /// `stopActivity` → wait for `.stopped` → `endCollection` →
    /// `finishWorkout` → `end()`. `.stopped` is not `.ended`, and calling
    /// `end()` before the builder finishes persists NOTHING — there is no
    /// save-on-end convenience. The tail of it lives in the session
    /// delegate, because `.stopped` arrives asynchronously.
    ///
    /// Returns whether the live builder owns the save. The caller reads
    /// the answer synchronously and skips `HealthRecorder` on true, so
    /// the decision can never depend on a callback that may not arrive.
    @discardableResult
    func finish(at date: Date, route: [CLLocation] = []) -> Bool {
        guard let session, ownsRecording else {
            clear()
            return false
        }
        // ⚠️ The route has to be handed over now and held: the tail of
        // the sequence runs from the session delegate, which is given a
        // state change and nothing else. Without this an outdoor run
        // recorded live would lose the map the retrospective write gave
        // it — the regression that would make the switch cost something.
        pendingRoute = route
        session.stopActivity(with: date)
        return true
    }

    /// Throw the recording away — the workout was discarded, so nothing
    /// should reach Health. Idempotent.
    func discard() {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        pendingRoute = []
        ownsRecording = false
        session.end()
        builder.discardWorkout()
    }

    /// Re-attach to a session that outlived the app, reporting whether one
    /// was found. Without this the sensors keep recording while the app
    /// insists nothing is running.
    ///
    /// ⚠️ Re-attaching means re-establishing the data source and BOTH
    /// delegates: recovery hands back the session object, not the wiring
    /// around it. The completion fires on EVERY path, "nothing to
    /// recover" included — a swallowed continuation is a workout that
    /// never starts recording.
    private func adoptRecoveredSession(_ completion: @escaping (Bool) -> Void) {
        HealthAccess.store.recoverActiveWorkoutSession { recovered, _ in
            Task { @MainActor [weak self] in
                guard let self, let recovered, self.session == nil else {
                    completion(false)
                    return
                }
                let builder = recovered.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(
                    healthStore: HealthAccess.store,
                    workoutConfiguration: recovered.workoutConfiguration
                )
                recovered.delegate = self
                builder.delegate = self
                self.session = recovered
                self.builder = builder
                self.ownsRecording = true
                completion(true)
            }
        }
    }

    private func clear() {
        session = nil
        builder = nil
        pendingRoute = []
        ownsRecording = false
    }

    /// The end sequence's tail, run once `.stopped` has actually landed.
    private func completeEnding(at date: Date) {
        guard let session, let builder else { return }
        let route = pendingRoute
        self.session = nil
        self.builder = nil
        pendingRoute = []
        ownsRecording = false
        Self.endAndSave(session: session, builder: builder, route: route, at: date)
    }

    /// ⚠️ `nonisolated` and static, taking the HealthKit objects as plain
    /// parameters, because neither is `Sendable` and the chain below runs
    /// on HealthKit's own queue. Same shape as `HealthRecorder.save`.
    private nonisolated static func endAndSave(
        session: HKWorkoutSession,
        builder: HKLiveWorkoutBuilder,
        route: [CLLocation],
        at date: Date
    ) {
        // The route builder is spun off the workout builder and fed the
        // fixes before collection ends; the route is ASSOCIATED after the
        // workout is saved, which is Apple's documented order and the
        // same one the retrospective writer follows. Every step is
        // guarded: a failure anywhere drops the map and keeps the
        // workout, because Health is a bonus, never a gate.
        let routeBuilder = route.isEmpty
            ? nil
            : builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
        let endAndFinish = {
            builder.endCollection(withEnd: date) { _, _ in
                builder.finishWorkout { workout, _ in
                    // ⚠️ `end()` LAST, and only once the builder has
                    // finished. Ending before it does silently persists
                    // nothing — there is no save-on-end convenience.
                    session.end()
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

// MARK: - HKWorkoutSessionDelegate

extension LiveWorkoutController: HKWorkoutSessionDelegate {
    /// ⚠️ `nonisolated`, hopping inside: HealthKit calls its delegates on
    /// its own queue, so declaring them `@MainActor` is a data race the
    /// compiler cannot see through an Objective-C protocol.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .stopped else { return }
        Task { @MainActor [weak self] in
            self?.completeEnding(at: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // The expected failure is `anotherWorkoutSessionStarted` — the
        // wrist's run view opened during a phone-driven workout and took
        // the sensors. Give up the claim rather than fight for it; the
        // caller's retrospective write is a complete fallback.
        Task { @MainActor [weak self] in
            self?.clear()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension LiveWorkoutController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let bpm = HKUnit.count().unitDivided(by: .minute())

        var latest: Int?
        var average: Int?
        var peak: Int?
        if collectedTypes.contains(heartRateType),
           let statistics = workoutBuilder.statistics(for: heartRateType) {
            latest = statistics.mostRecentQuantity().map { Int($0.doubleValue(for: bpm).rounded()) }
            average = statistics.averageQuantity().map { Int($0.doubleValue(for: bpm).rounded()) }
            peak = statistics.maximumQuantity().map { Int($0.doubleValue(for: bpm).rounded()) }
        }

        var kilocalories: Int?
        if collectedTypes.contains(energyType),
           let statistics = workoutBuilder.statistics(for: energyType),
           let sum = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()), sum > 0 {
            kilocalories = Int(sum.rounded())
        }

        let stamped = latest != nil ? Date() : nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let latest {
                self.latestBPM = latest
                self.latestBPMAt = stamped
            }
            if let average { self.averageBPM = average }
            if let peak { self.maxBPM = peak }
            if let kilocalories { self.activeEnergyKilocalories = kilocalories }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

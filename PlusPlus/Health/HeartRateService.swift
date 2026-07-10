import Foundation
import HealthKit
import Observation
import PlusPlusKit

/// The app's one Health doorway: a shared HKHealthStore, the
/// authorization asks, and the max-HR resolution zone math needs.
/// Health is a bonus, never a gate (the HealthRecorder rule):
/// unavailable, undecided, or denied all render as "no reading", and
/// everything is disabled under --uitest-reset so a permission sheet
/// can never eat a smoke test's tap.
enum HealthAccess {
    static let store = HKHealthStore()

    static let uitest = CommandLine.arguments.contains("--uitest-reset")

    static var isAvailable: Bool {
        !uitest && HKHealthStore.isHealthDataAvailable()
    }

    /// Everything the phone reads: live/summary heart rate, plus date
    /// of birth so zones resolve against a real max HR instead of the
    /// fallback.
    private static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKCharacteristicType(.dateOfBirth)]
    }

    /// The full ask — the welcome flow's Connect button and the
    /// Settings row. Reads + the workout write HealthRecorder performs.
    /// `success` means the request was processed, not that anything was
    /// granted (HealthKit never reveals read denial).
    static func requestEverything(completion: (() -> Void)? = nil) {
        guard isAvailable else {
            completion?()
            return
        }
        store.requestAuthorization(toShare: [.workoutType()], read: readTypes) { _, _ in
            DispatchQueue.main.async { completion?() }
        }
    }

    /// Read-side ask at workout start — shows the sheet only while
    /// undecided (installs that skipped the welcome ask), otherwise
    /// completes silently. The completion fires on EVERY path,
    /// unavailable included — a swallowed continuation is a hang for
    /// the next caller.
    static func requestRead(completion: @escaping () -> Void) {
        guard isAvailable else {
            completion()
            return
        }
        store.requestAuthorization(toShare: [], read: readTypes) { _, _ in
            DispatchQueue.main.async { completion() }
        }
    }

    /// The user's max HR for zone math: Health's date of birth when
    /// readable (220 − age), else a mid-30s fallback. Synchronous —
    /// characteristics are a local read, and callers (plan push, zone
    /// coloring) can't await.
    static func resolvedMaxHeartRate() -> Int {
        guard isAvailable,
              let components = try? store.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components),
              let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
        else { return HeartRate.fallbackMax }
        return HeartRate.estimatedMax(age: age)
    }
}

/// Live heart rate during a phone-run session: an anchored query over
/// Health's heartRate samples from session start, surfacing the newest
/// reading. With a watch on the wrist samples flow continuously (every
/// few minutes at rest, every few seconds during a watch workout); a
/// chest strap paired to Health works too. No sensor simply means no
/// reading — the UI shows nothing rather than something stale (readings
/// older than `freshWindow` don't render).
@Observable
final class HeartRateMonitor {
    /// How old a reading can be and still render as "live".
    static let freshWindow: TimeInterval = 180

    private(set) var latestBPM: Int?
    private(set) var latestAt: Date?
    /// Resolved when the query starts (date of birth may have just been
    /// granted by the welcome ask).
    private(set) var maxHeartRate = HeartRate.fallbackMax

    private var query: HKAnchoredObjectQuery?
    private var starting = false
    /// Bumped by every start AND stop, so a stale requestRead callback
    /// (its start superseded by a stop, or a stop/start pair) can never
    /// arm a query against an old start date.
    private var generation = 0

    func start(from startDate: Date) {
        guard HealthAccess.isAvailable, query == nil, !starting else { return }
        starting = true
        generation += 1
        let expected = generation
        HealthAccess.requestRead { [weak self] in
            guard let self, self.starting, self.generation == expected, self.query == nil else { return }
            self.starting = false
            self.maxHeartRate = HealthAccess.resolvedMaxHeartRate()

            let type = HKQuantityType(.heartRate)
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [])
            let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
                self?.adopt(samples)
            }
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit,
                resultsHandler: handler
            )
            query.updateHandler = handler
            self.query = query
            HealthAccess.store.execute(query)
        }
    }

    func stop() {
        starting = false
        generation += 1
        if let query {
            HealthAccess.store.stop(query)
        }
        query = nil
    }

    private func adopt(_ samples: [HKSample]?) {
        guard let newest = samples?
            .compactMap({ $0 as? HKQuantitySample })
            .max(by: { $0.endDate < $1.endDate })
        else { return }
        let bpm = Int(newest.quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Anchored updates arrive in insertion order, not sample
            // order — a watch batch can land after a fresher strap
            // reading. Keep the newest by sample time.
            if let latestAt, latestAt > newest.endDate { return }
            self.latestBPM = bpm
            self.latestAt = newest.endDate
        }
    }

    /// Session avg/max over a window, for the finish stamp and the
    /// record backfill. Answers nil when Health has nothing (no access,
    /// no samples) — never zero.
    static func summary(from start: Date, to end: Date, completion: @escaping (_ average: Int?, _ max: Int?) -> Void) {
        guard HealthAccess.isAvailable else {
            completion(nil, nil)
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKStatisticsQuery(
            quantityType: HKQuantityType(.heartRate),
            quantitySamplePredicate: predicate,
            options: [.discreteAverage, .discreteMax]
        ) { _, statistics, _ in
            let unit = HKUnit.count().unitDivided(by: .minute())
            let average = statistics?.averageQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
            let peak = statistics?.maximumQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
            DispatchQueue.main.async {
                completion(average, peak)
            }
        }
        HealthAccess.store.execute(query)
    }
}

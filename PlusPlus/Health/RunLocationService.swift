import Foundation
import CoreLocation
import Observation
import PlusPlusKit

/// Live pace + distance during an OUTDOOR run, from GPS. Same doctrine as
/// `HeartRateMonitor`: location is a bonus, never a gate — unavailable,
/// undecided, or denied all render as "no reading", and it's inert under
/// `--uitest-reset` so a permission sheet can never eat a smoke test's tap.
///
/// Unlike the watch (whose `HKWorkoutSession` owns GPS), the phone has no
/// live workout session, so this drives `CLLocationManager` directly and
/// runs it in the BACKGROUND (`allowsBackgroundLocationUpdates`) — a
/// pocketed, screen-off run still tracks, the way every running app works.
/// Distance is accumulated between good fixes and fed to a Kit
/// `LivePaceMeter`, which owns all the pace math.
@Observable
final class RunLocationMonitor: NSObject, CLLocationManagerDelegate {
    /// How old a reading can be and still render as "live" — matches the
    /// heart-rate monitor so the two vitals expire on the same clock.
    static let freshWindow: TimeInterval = HeartRateMonitor.freshWindow

    private(set) var currentPaceSeconds: Double?
    /// The run's overall moving pace — what a finished set logs as its
    /// actual (steady through a stop, unlike the trailing-window current).
    private(set) var averagePaceSeconds: Double?
    private(set) var totalMeters: Double?
    private(set) var latestAt: Date?
    private(set) var unit: DistanceUnit = .miles

    /// The measured distance so far, in the run's own unit (for logging a
    /// set's actual "1.24 mi"). nil before any distance accrues.
    var totalDistanceInUnit: Double? {
        totalMeters.map { unit.value(fromMeters: $0) }
    }

    /// Whether the published readings are current — a set's auto-log must
    /// never write a prior exercise's frozen values while the new meter is
    /// still acquiring GPS.
    var isFresh: Bool {
        guard let latestAt else { return false }
        return Date().timeIntervalSince(latestAt) < Self.freshWindow
    }

    /// Fastest plausible human running segment (~2:08 /mi); a fix implying
    /// more is a GPS teleport, not a stride — skip it (distance-side twin
    /// of LivePaceMeter's pace clamp).
    private let maxSpeed: Double = 12.5

    // Internal machinery — never observed (and `@Observable` forbids
    // `lazy`, so `manager` is configured in init instead).
    @ObservationIgnored private let uitest = CommandLine.arguments.contains("--uitest-reset")
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var meter: LivePaceMeter?
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var running = false
    /// Bumped by every start/stop so a late authorization callback can't
    /// arm updates against a superseded run (the HeartRateMonitor guard).
    @ObservationIgnored private var generation = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // A pocketed run must keep tracking; the OS shows the blue
        // indicator while it does.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    /// Begin tracking from the session start, denominated in the run's
    /// unit. Idempotent; a no-op under uitest or when already running.
    func start(from startDate: Date, unit: DistanceUnit) {
        guard !uitest, !running else { return }
        running = true
        generation += 1
        self.unit = unit
        self.startDate = startDate
        self.meter = LivePaceMeter(unit: unit)
        self.lastLocation = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // updates begin in the delegate callback
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break   // denied/restricted → no reading, run continues
        }
    }

    /// Hold tracking (workout paused): stop the GPS drain and mark a pause
    /// boundary so the paused gap counts as neither distance nor time.
    func pause() {
        guard running else { return }
        manager.stopUpdatingLocation()
        meter?.markPauseBoundary()
        lastLocation = nil
    }

    func resume() {
        guard running, !uitest else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        running = false
        generation += 1
        manager.stopUpdatingLocation()
        meter = nil
        startDate = nil
        lastLocation = nil
        // Clear the readings so a re-base for the NEXT exercise can't
        // auto-log this one's frozen distance/pace before GPS re-locks.
        currentPaceSeconds = nil
        averagePaceSeconds = nil
        totalMeters = nil
        latestAt = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard running else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running, let startDate, meter != nil else { return }
        let expected = generation
        for location in locations {
            // Reject cold-start / no-lock fixes and stale samples — the
            // meter only ever sees trustworthy distance.
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30 else { continue }
            let elapsed = location.timestamp.timeIntervalSince(startDate)
            guard elapsed >= 0 else { continue }
            if let last = lastLocation {
                let dt = location.timestamp.timeIntervalSince(last.timestamp)
                let segment = location.distance(from: last)
                // A good-accuracy fix can still teleport (urban canyon,
                // tunnel exit); ignore a segment implying a superhuman
                // speed rather than banking its distance, and wait for the
                // next honest fix from the last good position.
                if dt > 0, segment / dt > maxSpeed { continue }
                // Read the running total into a local first: mutating
                // `meter` while also reading it in the same expression is
                // an exclusivity violation.
                let cumulative = (meter?.totalMeters ?? 0) + segment
                meter?.ingest(at: elapsed, cumulativeMeters: cumulative)
            }
            // The first fix after a start/pause seeds position without
            // counting the gap to it as distance.
            lastLocation = location
        }
        guard generation == expected, let meter else { return }
        let pace = meter.currentPaceSeconds
        let average = meter.averagePaceSeconds
        let total = meter.totalMeters
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == expected else { return }
            self.currentPaceSeconds = pace
            self.averagePaceSeconds = average
            self.totalMeters = total
            self.latestAt = Date()
        }
    }
}

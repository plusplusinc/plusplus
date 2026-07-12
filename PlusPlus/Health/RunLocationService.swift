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

    private let uitest = CommandLine.arguments.contains("--uitest-reset")
    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.activityType = .fitness
        m.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        m.distanceFilter = kCLDistanceFilterNone
        // A pocketed run must keep tracking; the OS shows the blue
        // indicator while it does.
        m.allowsBackgroundLocationUpdates = true
        m.pausesLocationUpdatesAutomatically = false
        m.showsBackgroundLocationIndicator = true
        return m
    }()

    private var meter: LivePaceMeter?
    private var startDate: Date?
    private var lastLocation: CLLocation?
    private var running = false
    /// Bumped by every start/stop so a late authorization callback can't
    /// arm updates against a superseded run (the HeartRateMonitor guard).
    private var generation = 0

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
                meter?.ingest(at: elapsed, cumulativeMeters: (meter?.totalMeters ?? 0) + location.distance(from: last))
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

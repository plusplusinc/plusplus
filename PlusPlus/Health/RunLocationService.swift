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

    /// Every accepted fix of the WHOLE session in time order, flattened
    /// across segments — what HealthKit's route builder takes (a single
    /// HKWorkoutRoute is one polyline and can't encode a gap anyway).
    /// Read BEFORE `stop()`, which banks-then-holds nothing new.
    var sessionRoute: [CLLocation] {
        (bankedSegments + [routeFixes]).flatMap { $0 }
    }

    /// The session's durable track (#378): one `RouteTrack` segment per
    /// contiguous outdoor stretch — pauses and per-exercise re-bases are
    /// honest gap boundaries, unlike the flattened Health route. Altitude
    /// is carried only when the fix vouched for it (`verticalAccuracy`
    /// 0...25 m); `RouteTrack.init` applies its own sanitation. Read
    /// BEFORE `stop()`.
    var sessionTrack: RouteTrack {
        RouteTrack(segments: (bankedSegments + [routeFixes]).map { segment in
            segment.map { fix in
                RouteTrack.Fix(
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude,
                    elevation: (fix.verticalAccuracy > 0 && fix.verticalAccuracy <= 25) ? fix.altitude : nil,
                    time: fix.timestamp
                )
            }
        })
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
    /// The accepted fixes for the CURRENT contiguous segment, kept so the
    /// finished workout can be saved to Health with its GPS route (#348)
    /// and persisted as the session's track (#378). Only trustworthy fixes
    /// land here (the same accuracy + no-teleport gate distance uses), so
    /// the saved route is the same track the distance was measured from.
    @ObservationIgnored private var routeFixes: [CLLocation] = []
    /// Completed segments for the WHOLE session — `pause()` and `stop()`
    /// bank the live segment here, and unlike `routeFixes` it is NEVER
    /// cleared (the monitor is `@State` per session presentation, so its
    /// lifetime IS the reset). This is what fixes #348's last-segment-only
    /// limitation: an outdoor→strength→outdoor session keeps every stretch.
    @ObservationIgnored private var bankedSegments: [[CLLocation]] = []
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
        self.routeFixes = []

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
    /// The live segment banks — a pause is a track gap, and the resumed
    /// stretch is honestly a new segment (no more phantom straight line
    /// across a resume-elsewhere in OUR track; Health's single polyline
    /// still flattens, which is cosmetic there).
    func pause() {
        guard running else { return }
        manager.stopUpdatingLocation()
        meter?.markPauseBoundary()
        lastLocation = nil
        bankCurrentSegment()
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
        // Bank the live segment instead of dropping it (#378): the session
        // track keeps EVERY outdoor stretch, so an outdoor→strength→outdoor
        // session records whole. The finish path reads `sessionTrack` /
        // `sessionRoute` before stop(). Consequence, accepted in #378: a
        // mixed run+strength session now classifies as an outdoor run in
        // Health whenever ANY GPS segment exists, not only when a run came
        // last.
        bankCurrentSegment()
    }

    /// Move the live segment into the session archive. Sub-2-fix stubs are
    /// dropped here (a lone seed fix carries no distance and would be
    /// dropped by `RouteTrack.init` anyway — no reason to feed Health a
    /// point either).
    private func bankCurrentSegment() {
        if routeFixes.count >= 2 {
            bankedSegments.append(routeFixes)
        }
        routeFixes = []
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
            // 1 Hz cap (#378): CLLocation can burst-deliver; one stored fix
            // per second bounds the track (~800 KB GPX for a 2-hour run)
            // and guarantees the sidecar's whole-second timestamps never
            // collide. Distance isn't lost — the next accepted fix measures
            // from the last accepted one.
            if let last = lastLocation, location.timestamp.timeIntervalSince(last.timestamp) < 1 { continue }
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
            // Bank the accepted fix for the saved route. A mid-run teleport
            // hits the `continue` above, but the seed fix after a start or a
            // resume has no prior point to test against, so a run that was
            // paused and then resumed somewhere else can leave one straight
            // segment across the gap in the saved map. That's cosmetic only
            // (a single HKWorkoutRoute is one polyline and can't encode a
            // gap); the pause boundary already keeps the gap out of distance.
            routeFixes.append(location)
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

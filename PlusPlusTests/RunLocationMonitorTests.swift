import CoreLocation
import Foundation
import Testing
import PlusPlusKit
@testable import PlusPlus

/// The capture side of the run record (#378), driven by calling the
/// CLLocationManagerDelegate method directly with constructed fixes — the
/// only part of the GPS path a headless test can exercise (real capture
/// needs a device). Segment banking, the fix gates, and the track/route
/// accessors are all synchronous internal state, so no main-queue hop is
/// awaited.
@Suite("RunLocationMonitor capture")
struct RunLocationMonitorTests {
    private static let metersPerDegree = 6_371_000.0 * .pi / 180
    private let base = Date(timeIntervalSince1970: 1_752_000_000)
    private let manager = CLLocationManager()

    private func loc(
        meters: Double, seconds: TimeInterval,
        ele: Double = 10, vAcc: Double = 5, hAcc: Double = 5
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: meters / Self.metersPerDegree, longitude: 0),
            altitude: ele,
            horizontalAccuracy: hAcc,
            verticalAccuracy: vAcc,
            timestamp: base.addingTimeInterval(seconds)
        )
    }

    private func startedMonitor() -> RunLocationMonitor {
        let monitor = RunLocationMonitor()
        monitor.start(from: base, unit: .miles)
        return monitor
    }

    @Test("A pause banks the live segment; the session track keeps both")
    func pauseBanksSegment() {
        let monitor = startedMonitor()
        monitor.locationManager(manager, didUpdateLocations: [
            loc(meters: 0, seconds: 0), loc(meters: 50, seconds: 10), loc(meters: 100, seconds: 20),
        ])
        monitor.pause()
        monitor.locationManager(manager, didUpdateLocations: [
            loc(meters: 100, seconds: 100), loc(meters: 150, seconds: 110),
        ])
        let track = monitor.sessionTrack
        #expect(track.segments.count == 2)
        #expect(track.segments[0].count == 3)
        #expect(track.segments[1].count == 2)
        #expect(abs(track.totalMeters - 150) < 2)
        // The gap contributes no time: 20 s + 10 s of moving only.
        #expect(abs(track.movingSeconds - 30) < 0.5)
        #expect(monitor.sessionRoute.count == 5)
    }

    @Test("A re-base stop()+start() keeps the prior exercise's segment (#348 fix)")
    func rebaseKeepsPriorSegments() {
        let monitor = startedMonitor()
        monitor.locationManager(manager, didUpdateLocations: [
            loc(meters: 0, seconds: 0), loc(meters: 100, seconds: 20),
        ])
        monitor.stop()
        monitor.start(from: base, unit: .miles)
        monitor.locationManager(manager, didUpdateLocations: [
            loc(meters: 100, seconds: 200), loc(meters: 180, seconds: 220),
        ])
        let track = monitor.sessionTrack
        #expect(track.segments.count == 2)
        #expect(abs(track.totalMeters - 180) < 2)
    }

    @Test("Teleports and bad-accuracy fixes never reach the track")
    func gatesHold() {
        let monitor = startedMonitor()
        monitor.locationManager(manager, didUpdateLocations: [
            loc(meters: 0, seconds: 0),
            loc(meters: 1000, seconds: 10),          // 100 m/s — a teleport
            loc(meters: 30, seconds: 15, hAcc: 50),  // no lock
            loc(meters: 50, seconds: 20),
        ])
        let track = monitor.sessionTrack
        #expect(track.segments == [[
            RouteTrack.Fix(latitude: 0, longitude: 0, elevation: 10, time: base),
            RouteTrack.Fix(latitude: 50 / Self.metersPerDegree, longitude: 0, elevation: 10, time: base.addingTimeInterval(20)),
        ]])
    }

    @Test("The 1 Hz cap skips burst deliveries")
    func oneHzCap() {
        let monitor = startedMonitor()
        monitor.locationManager(manager, didUpdateLocations: [
            loc(meters: 0, seconds: 0),
            loc(meters: 5, seconds: 0.5),   // burst — skipped
            loc(meters: 20, seconds: 2),
        ])
        #expect(monitor.sessionRoute.count == 2)
        #expect(abs(monitor.sessionTrack.totalMeters - 20) < 2)
    }

    @Test("Altitude rides only a trusted vertical accuracy")
    func elevationGating() {
        let monitor = startedMonitor()
        monitor.locationManager(manager, didUpdateLocations: [
            loc(meters: 0, seconds: 0, ele: 10, vAcc: 5),
            loc(meters: 50, seconds: 10, ele: 12, vAcc: 40),   // untrusted altimeter
        ])
        let fixes = monitor.sessionTrack.segments[0]
        #expect(fixes[0].elevation == 10)
        #expect(fixes[1].elevation == nil)
    }
}

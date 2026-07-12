import Foundation
import Testing
@testable import PlusPlusKit

@Suite("LivePaceMeter")
struct LivePaceMeterTests {
    /// Feed a constant speed (m/s) once per second up to `seconds`.
    private func steady(_ meter: inout LivePaceMeter, speed: Double, seconds: Int, from: Int = 0) {
        for t in from...seconds {
            meter.ingest(at: TimeInterval(t), cumulativeMeters: speed * Double(t))
        }
    }

    @Test("Steady pace resolves to the split for that speed")
    func steadyPace() throws {
        var meter = LivePaceMeter(unit: .miles)
        steady(&meter, speed: 3, seconds: 30) // 3 m/s ≈ 8:56 /mi
        let pace = try #require(meter.currentPaceSeconds)
        // 1609.344 / 3 = 536.4 s per mile.
        #expect(abs(pace - 536.4) < 1.0)
        #expect(abs(meter.totalMeters - 90) < 0.001)
    }

    @Test("A cold start (too little spanned data) reads nil, not a wild number")
    func coldStart() {
        var meter = LivePaceMeter(unit: .miles)
        steady(&meter, speed: 3, seconds: 5) // span 5 s < minSpan 8 s
        #expect(meter.currentPaceSeconds == nil)
    }

    @Test("Standing still drives current pace to nil once the window is stopped")
    func stoppedDegrades() {
        var meter = LivePaceMeter(unit: .miles)
        steady(&meter, speed: 3, seconds: 20)
        #expect(meter.currentPaceSeconds != nil)
        // Now hold position (cumulative distance flat) past the full window.
        for t in 21...45 {
            meter.ingest(at: TimeInterval(t), cumulativeMeters: 60)
        }
        #expect(meter.currentPaceSeconds == nil)
        // The overall moving average survives the stop.
        #expect(meter.averagePaceSeconds != nil)
    }

    @Test("A pause gap counts as neither distance nor moving time")
    func pauseBoundary() throws {
        var meter = LivePaceMeter(unit: .miles)
        steady(&meter, speed: 3, seconds: 10) // 30 m over ~9 s moving
        meter.markPauseBoundary()
        // Resume 90 s later; distance picks up from where it left off.
        meter.ingest(at: 100, cumulativeMeters: 30) // reseed, no phantom gap
        for t in 101...110 {
            meter.ingest(at: TimeInterval(t), cumulativeMeters: 30 + 3 * Double(t - 100))
        }
        let avg = try #require(meter.averagePaceSeconds)
        // Had the 90 s pause counted, average speed would collapse toward
        // ~0.5 m/s (pace > 3000 s). A true moving pace stays sane.
        #expect(avg < 700)
    }

    @Test("A GPS teleport is rejected by the plausibility clamp")
    func gpsSpike() {
        var meter = LivePaceMeter(unit: .miles)
        steady(&meter, speed: 3, seconds: 20) // 60 m
        // One fix jumps 500 m in a second — a superhuman split.
        meter.ingest(at: 21, cumulativeMeters: 560)
        // Resulting window speed lands outside DistanceUnit.paceRange → nil.
        #expect(meter.currentPaceSeconds == nil)
    }

    @Test("Backward distance never walks the total down")
    func monotonicGuard() {
        var meter = LivePaceMeter(unit: .miles)
        meter.ingest(at: 0, cumulativeMeters: 100)
        meter.ingest(at: 1, cumulativeMeters: 90) // a jittered smaller reading
        #expect(meter.totalMeters == 100)
    }

    @Test("Pace is denominated by the unit's reference distance")
    func unitReference() throws {
        var erg = LivePaceMeter(unit: .meters) // per 500 m
        steady(&erg, speed: 3, seconds: 30)
        let ergPace = try #require(erg.currentPaceSeconds)
        #expect(abs(ergPace - 500.0 / 3.0) < 1.0) // ≈ 2:47 /500m

        var km = LivePaceMeter(unit: .kilometers)
        steady(&km, speed: 3, seconds: 30)
        let kmPace = try #require(km.currentPaceSeconds)
        #expect(abs(kmPace - 1000.0 / 3.0) < 1.0) // ≈ 5:33 /km
    }

    @Test("A fresh meter and a reset meter report nothing")
    func emptyAndReset() {
        var meter = LivePaceMeter(unit: .miles)
        #expect(meter.currentPaceSeconds == nil)
        #expect(meter.averagePaceSeconds == nil)
        steady(&meter, speed: 3, seconds: 20)
        meter.reset()
        #expect(meter.currentPaceSeconds == nil)
        #expect(meter.averagePaceSeconds == nil)
        #expect(meter.totalMeters == 0)
    }
}

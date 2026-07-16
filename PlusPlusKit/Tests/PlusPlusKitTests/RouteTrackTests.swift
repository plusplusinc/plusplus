import Foundation
import Testing
@testable import PlusPlusKit

@Suite("RouteTrack")
struct RouteTrackTests {
    /// Meters per degree of latitude on the haversine sphere — moving along
    /// a meridian makes synthetic distances exact (R·dφ), so tests can
    /// place a fix "at N meters" and trust the derivations to sub-meter
    /// precision (coordinate quantization costs ~0.06 m per fix).
    private static let metersPerDegree = 6_371_000.0 * .pi / 180

    private let start = Date(timeIntervalSince1970: 1_752_000_000)

    private func fix(meters: Double, seconds: TimeInterval, ele: Double? = nil) -> RouteTrack.Fix {
        RouteTrack.Fix(
            latitude: meters / Self.metersPerDegree,
            longitude: 0,
            elevation: ele,
            time: start.addingTimeInterval(seconds)
        )
    }

    // MARK: - Construction

    @Test("Init quantizes to sidecar precision")
    func quantization() {
        let fix = RouteTrack.Fix(
            latitude: 37.77492949, longitude: -122.41941662,
            elevation: 12.34, time: Date(timeIntervalSince1970: 1000.6)
        )
        #expect(fix.latitude == 37.774929)
        #expect(fix.longitude == -122.419417)
        #expect(fix.elevation == 12.3)
        #expect(fix.time == Date(timeIntervalSince1970: 1001))
    }

    @Test("Init drops non-ascending fixes and sub-2-fix segments")
    func sanitation() {
        let a = fix(meters: 0, seconds: 0)
        let rewound = fix(meters: 50, seconds: 0)   // same quantized second
        let b = fix(meters: 100, seconds: 10)
        let track = RouteTrack(segments: [[a, rewound, b], [fix(meters: 0, seconds: 100)], []])
        #expect(track.segments == [[a, b]])
        #expect(RouteTrack(segments: []).isEmpty)
    }

    @Test("Init drops non-finite coordinates and nulls non-finite elevations")
    func nonFiniteSanitation() {
        let a = fix(meters: 0, seconds: 0)
        let poisonedLat = RouteTrack.Fix(latitude: .nan, longitude: 0, time: start.addingTimeInterval(5))
        let infiniteEle = RouteTrack.Fix(
            latitude: 100 / Self.metersPerDegree, longitude: 0,
            elevation: .infinity, time: start.addingTimeInterval(10)
        )
        let track = RouteTrack(segments: [[a, poisonedLat, infiniteEle]])
        #expect(track.segments.count == 1)
        #expect(track.segments[0].count == 2)   // the NaN-lat fix is gone
        #expect(track.segments[0][1].elevation == nil)
        #expect(track.totalMeters.isFinite)
        #expect(track.elevationGainMeters == nil)   // no finite pair survives
    }

    // MARK: - Distance and time

    @Test("Haversine matches a known meridian degree")
    func haversine() {
        let oneDegree = RouteTrack.haversineMeters(lat1: 0, lon1: 0, lat2: 1, lon2: 0)
        #expect(abs(oneDegree - 111_194.93) < 1)
    }

    @Test("Distance sums within segments, never across the gap")
    func distanceRespectsGaps() {
        let track = RouteTrack(segments: [
            [fix(meters: 0, seconds: 0), fix(meters: 600, seconds: 60)],
            // Resumed 4,000 m away — the jump must not count.
            [fix(meters: 5000, seconds: 300), fix(meters: 5400, seconds: 340)],
        ])
        #expect(abs(track.totalMeters - 1000) < 1)
    }

    @Test("Moving time excludes stopped intervals and pause gaps")
    func movingTime() {
        let track = RouteTrack(segments: [
            [
                fix(meters: 0, seconds: 0),
                fix(meters: 100, seconds: 10),   // 10 m/s: moving
                fix(meters: 101, seconds: 40),   // 0.03 m/s: standing at a light
                fix(meters: 201, seconds: 50),   // moving again
            ],
            [fix(meters: 300, seconds: 500), fix(meters: 400, seconds: 510)],
        ])
        // 10 + 10 + 10 moving seconds; the 30 s light and the 450 s pause gap don't accrue.
        #expect(abs(track.movingSeconds - 30) < 0.1)
    }

    @Test("Average pace quotes moving time per unit reference")
    func averagePace() {
        let track = RouteTrack(segments: [[fix(meters: 0, seconds: 0), fix(meters: 1000, seconds: 300)]])
        let perKm = try! #require(track.averagePaceSeconds(per: .kilometers))
        #expect(abs(perKm - 300) < 1)
        #expect(RouteTrack(segments: []).averagePaceSeconds(per: .kilometers) == nil)
    }

    // MARK: - Elevation

    @Test("Elevation gain is nil without altitude data")
    func elevationNil() {
        let track = RouteTrack(segments: [[fix(meters: 0, seconds: 0), fix(meters: 100, seconds: 10)]])
        #expect(track.elevationGainMeters == nil)
    }

    @Test("A flat noisy run gains nothing")
    func elevationNoise() {
        // A periodic ±2 m altimeter toggle — the worst case for a median
        // filter (the oscillation IS the window majority); only the
        // deadband stops it accruing.
        let sawtooth = (0..<40).map { i in
            fix(meters: Double(i) * 25, seconds: Double(i) * 10, ele: 10 + (i.isMultiple(of: 2) ? 2.0 : -2.0))
        }
        #expect(RouteTrack(segments: [sawtooth]).elevationGainMeters == 0)

        // Isolated spikes — the median's job.
        let spiky = (0..<40).map { i in
            fix(meters: Double(i) * 25, seconds: Double(i) * 10, ele: i.isMultiple(of: 7) ? 24.0 : 10.0)
        }
        #expect(RouteTrack(segments: [spiky]).elevationGainMeters == 0)
    }

    @Test("A steady climb counts within the hysteresis band")
    func elevationClimb() {
        // 0 → 50 m over 100 fixes, then back down (descent never subtracts).
        let up = (0..<100).map { i in
            fix(meters: Double(i) * 25, seconds: Double(i) * 10, ele: Double(i) * 0.5)
        }
        let down = (0..<100).map { i in
            fix(meters: 2500 + Double(i) * 25, seconds: 1000 + Double(i) * 10, ele: 50 - Double(i) * 0.5)
        }
        let track = RouteTrack(segments: [up + down])
        let gain = try! #require(track.elevationGainMeters)
        #expect(gain > 44 && gain <= 50)
    }

    // MARK: - Splits

    @Test("Constant pace cuts even splits plus a normalized partial")
    func splits() {
        // 10 m/s, a fix every 50 m: 1,250 m in 125 s.
        let fixes = (0...25).map { i in fix(meters: Double(i) * 50, seconds: Double(i) * 5) }
        let track = RouteTrack(segments: [fixes])
        let splits = track.splits(per: .meters)   // 500 m buckets

        #expect(splits.count == 3)
        #expect(splits.map(\.index) == [1, 2, 3])
        #expect(abs(splits[0].meters - 500) < 0.5 && abs(splits[0].seconds - 50) < 0.5)
        #expect(abs(splits[1].seconds - 50) < 0.5)
        #expect(abs(splits[2].meters - 250) < 0.5 && abs(splits[2].seconds - 25) < 0.5)
        // The partial quotes a full-bucket pace, not its tiny absolute time.
        #expect(abs(splits[2].paceSeconds - 50) < 0.5)
    }

    @Test("Split boundaries interpolate inside a long step")
    func splitInterpolation() {
        // One 600 m step in 60 s: the 500 m boundary lands mid-step.
        let track = RouteTrack(segments: [[fix(meters: 0, seconds: 0), fix(meters: 600, seconds: 60)]])
        let splits = track.splits(per: .meters)
        #expect(splits.count == 2)
        #expect(abs(splits[0].seconds - 50) < 0.5)
        #expect(abs(splits[1].meters - 100) < 0.5 && abs(splits[1].seconds - 10) < 0.5)
    }

    @Test("Pause gaps add no time to the split they straddle")
    func splitsAcrossGap() {
        let track = RouteTrack(segments: [
            [fix(meters: 0, seconds: 0), fix(meters: 600, seconds: 60)],
            [fix(meters: 600, seconds: 500), fix(meters: 1000, seconds: 540)],
        ])
        let splits = track.splits(per: .meters)
        #expect(splits.count == 2)
        // Split 2 = 100 m of segment 1 (10 s) + 400 m of segment 2 (40 s); the 440 s gap is absent.
        #expect(abs(splits[1].seconds - 50) < 0.5)
    }

    @Test("A sub-meter remainder is dropped, not a fourth split")
    func splitRemainder() {
        let fixes = [fix(meters: 0, seconds: 0), fix(meters: 1000.4, seconds: 100)]
        let splits = RouteTrack(segments: [fixes]).splits(per: .meters)
        #expect(splits.count == 2)
    }

    // MARK: - Elapsed-at-distance

    @Test("Elapsed time interpolates at a distance")
    func elapsedAt() {
        let fixes = (0...25).map { i in fix(meters: Double(i) * 50, seconds: Double(i) * 5) }
        let track = RouteTrack(segments: [fixes])
        let at750 = try! #require(track.elapsedSeconds(atMeters: 750))
        #expect(abs(at750 - 75) < 0.5)
        #expect(track.elapsedSeconds(atMeters: 0) == 0)
        #expect(track.elapsedSeconds(atMeters: 99_999) == nil)
        #expect(track.elapsedSeconds(atMeters: -1) == nil)
    }
}

import Foundation

/// A recorded GPS track — the durable shape of an outdoor run (#378). Pure
/// value math over timestamped fixes: the phone hands it `CLLocation`-derived
/// points, the GPX codec hands it parsed files, and every derivation
/// (distance, moving time, elevation gain, splits) is deterministic and
/// unit-tested on Linux. `LivePaceMeter` answers "how fast am I right now";
/// this answers "what happened", after the fact, from the same raw truth.
///
/// A track is SEGMENTS of contiguous recording: a pause/resume or a
/// per-exercise GPS re-engagement starts a new segment. Distance and time
/// never accrue across the gap between segments — a run paused at a café and
/// resumed two blocks away contributes no phantom distance.
public struct RouteTrack: Equatable, Sendable {
    /// One GPS fix. Values are QUANTIZED at construction — 1e-6° latitude/
    /// longitude, 0.1 m elevation, whole-second UTC time — exactly the
    /// precision the GPX sidecar writes, so a track survives an
    /// encode → decode round trip bit-for-bit (`GPXTests` pins the fixed
    /// point). Quantization here, not in the codec, keeps every derivation
    /// working on the numbers that will actually be stored.
    public struct Fix: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        /// Meters above sea level; nil when the receiver had no trusted
        /// altitude (the capture path gates on vertical accuracy).
        public var elevation: Double?
        public var time: Date

        public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date) {
            self.latitude = (latitude * 1_000_000).rounded() / 1_000_000
            self.longitude = (longitude * 1_000_000).rounded() / 1_000_000
            self.elevation = elevation.map { ($0 * 10).rounded() / 10 }
            self.time = Date(timeIntervalSince1970: time.timeIntervalSince1970.rounded())
        }
    }

    /// One elapsed-distance bucket of the track — "mile 3 took 8:31".
    public struct Split: Equatable, Sendable {
        /// 1-based position in the run.
        public var index: Int
        /// Bucket length in meters — the unit's pace reference, except a
        /// shorter final partial.
        public var meters: Double
        /// Wall time spent inside the bucket, inter-segment gaps excluded.
        /// Deliberately NOT gated on moving speed: standing at a light IS
        /// part of what that kilometer took. (`movingSeconds` is the gated
        /// figure, for the run's honest average.)
        public var seconds: TimeInterval
        /// Seconds normalized to a FULL bucket, so a partial final split
        /// quotes a comparable pace, not a tiny absolute time.
        public var paceSeconds: Double
    }

    /// Below this the wearer is standing, not moving — the same floor
    /// `LivePaceMeter` uses live, so the finish-line average agrees with
    /// what the runner watched mid-run.
    public static let movingSpeedFloorMetersPerSecond: Double = 0.4

    /// A climb must rise this far above the running anchor (after
    /// smoothing) before it counts. GPS altitude wanders several meters
    /// sample to sample, and without a deadband a flat run "gains" hundreds
    /// of meters. 5 m because the deadband must exceed noise
    /// PEAK-TO-PEAK: a periodic ±2 m altimeter toggle sails through any
    /// median filter (period-2 oscillation IS the window majority), and
    /// only the deadband stops it accruing. Undercounting a true climb by
    /// up to one band is the accepted cost — never overstate.
    static let elevationHysteresisMeters: Double = 5

    /// Sub-meter final-split remainders are floating-point crumbs from the
    /// boundary walk, not distance a runner covered — dropped.
    static let minimumPartialSplitMeters: Double = 1

    /// Contiguous recording stretches, in time order. Construction
    /// sanitizes: within a segment only strictly-ascending timestamps
    /// survive (a duplicate or rewound fix is dropped), and a segment left
    /// with fewer than two fixes carries no distance or time and is dropped
    /// whole.
    public private(set) var segments: [[Fix]]

    public init(segments: [[Fix]]) {
        self.segments = segments.map { segment in
            var kept: [Fix] = []
            kept.reserveCapacity(segment.count)
            for fix in segment {
                if let last = kept.last, fix.time <= last.time { continue }
                kept.append(fix)
            }
            return kept
        }
        .filter { $0.count >= 2 }
    }

    public var isEmpty: Bool { segments.isEmpty }

    // MARK: - Derived measurements

    /// Haversine distance summed pairwise within segments — never across
    /// the gap between them.
    public var totalMeters: Double {
        var total = 0.0
        forEachStep { distance, _ in total += distance }
        return total
    }

    /// Time spent actually moving (pairwise speed at or above
    /// `movingSpeedFloorMetersPerSecond`), inter-segment gaps excluded.
    public var movingSeconds: TimeInterval {
        var moving: TimeInterval = 0
        forEachStep { distance, dt in
            if distance / dt >= Self.movingSpeedFloorMetersPerSecond { moving += dt }
        }
        return moving
    }

    /// Cumulative climb in meters: per segment, the elevation series is
    /// smoothed with a centered moving median (radius 2, lower median on
    /// even windows) and positive movement accrues through a deadband —
    /// only once the smoothed value rises `elevationHysteresisMeters` above
    /// the running anchor, which a descent re-anchors. Deterministic, and a
    /// flat-but-noisy run reads ~0 instead of the naive sum's fiction.
    /// nil when no segment carries two elevations to compare.
    public var elevationGainMeters: Double? {
        var gain = 0.0
        var sawElevation = false
        for segment in segments {
            let series = segment.compactMap(\.elevation)
            guard series.count >= 2 else { continue }
            sawElevation = true
            let smoothed = Self.movingMedian(series, radius: 2)
            var anchor = smoothed[0]
            for value in smoothed.dropFirst() {
                if value >= anchor + Self.elevationHysteresisMeters {
                    gain += value - anchor
                    anchor = value
                } else if value <= anchor - Self.elevationHysteresisMeters {
                    anchor = value
                }
            }
        }
        return sawElevation ? gain : nil
    }

    /// The run's overall pace: moving time over distance, quoted per the
    /// unit's reference (500 m / km / mi). nil before any moving distance.
    public func averagePaceSeconds(per unit: DistanceUnit) -> Double? {
        let meters = totalMeters
        let moving = movingSeconds
        guard meters > 0, moving > 0 else { return nil }
        return moving / (meters / unit.paceReferenceMeters)
    }

    /// The track cut into `unit.paceReferenceMeters` buckets — the same
    /// reference the pace vocabulary quotes against, so a `/mi` exercise
    /// gets mile splits and an erg-style meters unit gets 500 m splits.
    /// Bucket boundary times are linearly interpolated between the
    /// straddling fixes; a final partial below
    /// `minimumPartialSplitMeters` is dropped.
    public func splits(per unit: DistanceUnit) -> [Split] {
        let bucket = unit.paceReferenceMeters
        var splits: [Split] = []
        var bucketSeconds: TimeInterval = 0
        var bucketMeters = 0.0

        func closeSplit() {
            splits.append(Split(
                index: splits.count + 1,
                meters: bucketMeters,
                seconds: bucketSeconds,
                paceSeconds: bucketMeters > 0 ? bucketSeconds / (bucketMeters / bucket) : 0
            ))
            bucketSeconds = 0
            bucketMeters = 0
        }

        forEachStep { distance, dt in
            var remainingMeters = distance
            var remainingSeconds = dt
            while remainingMeters > 0, bucketMeters + remainingMeters >= bucket {
                let need = bucket - bucketMeters
                let fraction = need / remainingMeters
                let carved = remainingSeconds * fraction
                bucketSeconds += carved
                bucketMeters = bucket
                remainingMeters -= need
                remainingSeconds -= carved
                closeSplit()
            }
            bucketMeters += remainingMeters
            bucketSeconds += remainingSeconds
        }

        if bucketMeters >= Self.minimumPartialSplitMeters {
            closeSplit()
        }
        return splits
    }

    /// On-course time (inter-segment gaps excluded) when the track first
    /// reaches `atMeters`, linearly interpolated within the crossing step —
    /// "how long to 5 km". The feed a structured-run sequencer needs for
    /// "next interval starts at 2.0 km" (#380). nil outside 0...total.
    public func elapsedSeconds(atMeters target: Double) -> TimeInterval? {
        guard target >= 0 else { return nil }
        if target == 0 { return segments.isEmpty ? nil : 0 }
        var covered = 0.0
        var elapsed: TimeInterval = 0
        var reached: TimeInterval?
        forEachStep { distance, dt in
            if reached == nil, distance > 0, covered + distance >= target {
                reached = elapsed + dt * ((target - covered) / distance)
            }
            covered += distance
            elapsed += dt
        }
        return reached
    }

    // MARK: - Internals

    /// Walks every consecutive fix pair within segments (never across the
    /// gap), yielding the pair's haversine meters and positive seconds.
    private func forEachStep(_ body: (_ meters: Double, _ seconds: TimeInterval) -> Void) {
        for segment in segments {
            for (a, b) in zip(segment, segment.dropFirst()) {
                let dt = b.time.timeIntervalSince(a.time)
                guard dt > 0 else { continue }
                let d = Self.haversineMeters(
                    lat1: a.latitude, lon1: a.longitude,
                    lat2: b.latitude, lon2: b.longitude
                )
                body(d, dt)
            }
        }
    }

    /// Great-circle distance on the mean-radius sphere — the standard
    /// fitness-app approximation (ellipsoid corrections are far below GPS
    /// noise at run scale).
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dφ = (lat2 - lat1) * .pi / 180
        let dλ = (lon2 - lon1) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Centered moving median; the window shrinks at the edges, and an
    /// even-sized window takes the lower median — every choice fixed so the
    /// smoothing is reproducible anywhere.
    static func movingMedian(_ values: [Double], radius: Int) -> [Double] {
        guard values.count > 1, radius > 0 else { return values }
        return values.indices.map { i in
            let lo = max(0, i - radius)
            let hi = min(values.count - 1, i + radius)
            let window = values[lo...hi].sorted()
            return window[(window.count - 1) / 2]
        }
    }
}

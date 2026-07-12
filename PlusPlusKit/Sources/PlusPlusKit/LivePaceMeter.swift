import Foundation

/// Turns a stream of cumulative-distance samples into a live pace — the
/// "current pace" a runner reads mid-stride, plus a moving average for the
/// finish. Platform-pure: the phone feeds it raw `CLLocation`-derived
/// distance, the watch feeds it HealthKit's fused `distanceWalkingRunning`,
/// and neither device's framework leaks in here, so all the tricky math
/// (windowing, degrade-on-stop, GPS-spike rejection) is unit-tested on
/// Linux with synthetic samples.
///
/// Callers pass a MONOTONIC running total (`cumulativeMeters`), never a
/// per-fix delta — a jittered fix can't subtract distance, and a dropped
/// update just widens the next interval.
public struct LivePaceMeter: Equatable, Sendable {
    /// The distance a pace is quoted over (per mile / km / 500 m).
    public let unit: DistanceUnit
    /// How far back "current pace" averages — long enough to smooth
    /// per-fix GPS noise, short enough to track a real surge.
    public let window: TimeInterval
    /// Below this the runner is stopped, not slow: current pace reads nil
    /// (the UI shows "—") instead of an exploding split, and the interval
    /// doesn't count toward moving time.
    public let minSpeed: Double
    /// A current-pace reading needs at least this much spanned data, so a
    /// cold GPS start doesn't flash a wild number before the fixes settle.
    public let minSpan: TimeInterval

    private struct Sample: Equatable {
        var t: TimeInterval
        var meters: Double
    }

    /// The trailing-window ring: the newest sample plus a left-edge anchor
    /// at/just-before `window` seconds ago.
    private var samples: [Sample] = []
    private var lastT: TimeInterval?
    private var lastMeters: Double?
    /// Moving time only — intervals below `minSpeed` (a red light) and the
    /// gap across a pause don't accrue, so the average is a true pace.
    private var movingSeconds: TimeInterval = 0
    /// The next interval seeds position without counting distance or time
    /// (the sample straddling a pause).
    private var pausePending = false

    public private(set) var totalMeters: Double = 0

    public init(
        unit: DistanceUnit,
        window: TimeInterval = 20,
        minSpeedMetersPerSecond: Double = 0.4,
        minSpan: TimeInterval = 8
    ) {
        self.unit = unit
        self.window = window
        self.minSpeed = minSpeedMetersPerSecond
        self.minSpan = minSpan
    }

    /// Feed a cumulative distance at `t` seconds since the run started.
    public mutating func ingest(at t: TimeInterval, cumulativeMeters rawMeters: Double) {
        // Never let a bad fix walk the total backward.
        let meters = max(rawMeters, lastMeters ?? rawMeters)

        if let lastT, let lastMeters, !pausePending {
            let dt = t - lastT
            if dt > 0 {
                let speed = (meters - lastMeters) / dt
                if speed >= minSpeed { movingSeconds += dt }
            }
        }
        pausePending = false

        totalMeters = meters
        lastT = t
        lastMeters = meters
        samples.append(Sample(t: t, meters: meters))

        // Keep the window: drop everything older than the anchor, where the
        // anchor is the newest sample at/just-before `t - window`.
        let cutoff = t - window
        while samples.count >= 2, samples[1].t <= cutoff {
            samples.removeFirst()
        }
    }

    /// Trailing-window pace, seconds per `unit`. nil when there isn't
    /// enough spanned data yet, the runner is below `minSpeed` (stopped),
    /// or the result lands outside the unit's plausible band (a GPS spike).
    public var currentPaceSeconds: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.t - first.t
        guard span >= minSpan else { return nil }
        let distance = last.meters - first.meters
        let speed = distance / span
        guard speed >= minSpeed else { return nil }
        let pace = unit.paceReferenceMeters / speed
        guard unit.paceRange.contains(pace) else { return nil }
        return pace
    }

    /// Cumulative distance over moving time — the run's overall pace,
    /// steady through a stop. nil before any moving distance accrues.
    public var averagePaceSeconds: Double? {
        guard totalMeters > 0, movingSeconds > 0 else { return nil }
        let speed = totalMeters / movingSeconds
        guard speed > 0 else { return nil }
        return unit.paceReferenceMeters / speed
    }

    /// Mark a pause: the next `ingest` reseeds position without counting
    /// the paused gap. Clears the window so current pace ages to nil at
    /// once and resume starts fresh (the running total is preserved).
    public mutating func markPauseBoundary() {
        pausePending = true
        samples.removeAll(keepingCapacity: true)
    }

    /// Start over — a new run on the same meter.
    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        lastT = nil
        lastMeters = nil
        movingSeconds = 0
        pausePending = false
        totalMeters = 0
    }
}

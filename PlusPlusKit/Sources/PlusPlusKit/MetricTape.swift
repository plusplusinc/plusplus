import Foundation

/// The pure geometry behind the horizontal tape scrubber (the
/// iOS-27-timer-style ruler the app uses to pick a continuous quantity
/// with fine precision): a linear unit ↔ points mapping, clamping, and
/// the tick schedule. A "unit" is the tape's smallest addressable step —
/// one second for durations, one meter or one hundredth of a mile for
/// distance, one calorie — so all arithmetic stays integer and
/// Linux-testable; the SwiftUI layer converts units to the metric's real
/// value (a `quantum`) and formats. Generalized from the duration-only
/// `DurationTape` (2026-07-19) so distance and calories scrub the same
/// way — same split as `WorkoutMetric.wheelValues`, which owns nothing
/// numeric in the view.
public struct MetricTape: Equatable, Sendable {
    /// Whole units the tape spans, inclusive.
    public let range: ClosedRange<Int>
    /// Horizontal points per unit. Tuned per metric so one flick covers a
    /// sensible span while a single unit stays a deliberate finger
    /// movement (precise but not twitchy).
    public let pointsPerUnit: Double
    /// Units between minor tick marks.
    public let minorStride: Int
    /// Units between LABELED ticks — a multiple of `minorStride`.
    public let labelStride: Int

    public init(range: ClosedRange<Int>, pointsPerUnit: Double, minorStride: Int, labelStride: Int) {
        self.range = range
        self.pointsPerUnit = max(pointsPerUnit, 0.01)
        self.minorStride = max(minorStride, 1)
        self.labelStride = max(labelStride, max(minorStride, 1))
    }

    /// Total tape length in points (0 at `range.lowerBound`).
    public var length: Double {
        Double(range.upperBound - range.lowerBound) * pointsPerUnit
    }

    public func clamped(_ unit: Int) -> Int {
        min(max(unit, range.lowerBound), range.upperBound)
    }

    /// Tape offset (points from the lower bound) for a value.
    public func offset(for unit: Int) -> Double {
        Double(clamped(unit) - range.lowerBound) * pointsPerUnit
    }

    /// Nearest whole unit for a tape offset; out-of-range offsets
    /// (rubber-band overshoot) clamp to the bounds.
    public func unit(atOffset offset: Double) -> Int {
        clamped(range.lowerBound + Int((offset / pointsPerUnit).rounded()))
    }

    // MARK: - Ticks

    public struct Tick: Equatable, Sendable {
        public let unit: Int
        /// On the `labelStride` grid — the SwiftUI layer draws these with
        /// text (the metric's formatted value) and the rest as plain marks.
        public let isLabeled: Bool
    }

    /// Ticks whose tape offsets fall inside `window` (exactly — callers pad
    /// the window for edge drawing), ordered ascending. The visible-viewport
    /// query, so a long tape never enumerates every mark per frame. Marks
    /// sit every `minorStride`; labels every `labelStride`.
    public func ticks(in window: ClosedRange<Double>) -> [Tick] {
        let lowExact = Double(range.lowerBound) + window.lowerBound / pointsPerUnit
        let highExact = Double(range.lowerBound) + window.upperBound / pointsPerUnit
        // First multiple of the minor stride inside both the window and the
        // range…
        let firstInRange = Int((Double(range.lowerBound) / Double(minorStride)).rounded(.up)) * minorStride
        var u = max(firstInRange, Int((lowExact / Double(minorStride)).rounded(.up)) * minorStride)
        // …through the last such multiple inside both.
        let highest = min(range.upperBound, Int((highExact / Double(minorStride)).rounded(.down)) * minorStride)
        var result: [Tick] = []
        while u <= highest {
            result.append(Tick(unit: u, isLabeled: u % labelStride == 0))
            u += minorStride
        }
        return result
    }
}

public extension WorkoutMetric {
    /// True for the metrics picked on the horizontal tape scrubber instead
    /// of the tiered wheel: the time spans plus the wide-range continuous
    /// work metrics (distance, calories), where fine precision over a long
    /// range is the point and a uniform wheel would be an unwieldy list (a
    /// per-calorie wheel is 2000 rows; distance to 50 km, 2000). Loads
    /// (weight), short lists (reps), and machine dials keep the wheel.
    /// Exhaustive on purpose, like `isTimeSpan`/`step`/`range` — a new
    /// metric must DECIDE its picker, not silently fall to the wheel.
    var usesTapeScrubber: Bool {
        switch self {
        case .duration, .rest, .transition, .distance, .calories:
            true
        case .weight, .assistance, .reps, .height, .pace, .speed,
             .incline, .resistance, .power, .cadence, .rpe:
            false
        }
    }

    /// The scrubber tape for this metric plus the value one tape unit
    /// represents (its `quantum`), or nil for wheel metrics. Time spans and
    /// metered distance address whole units (1 s, 1 m); mile/kilometer
    /// distance addresses hundredths, so 3.14 mi is reachable. The strides
    /// echo the wheel's old grain (25 m, 0.25 mi/km, 5 cal) so the tape
    /// reads familiar, while landing on any whole unit between them.
    func scrubberTape(distanceUnit: DistanceUnit = .meters) -> (quantum: Double, tape: MetricTape)? {
        switch self {
        case .duration, .rest, .transition:
            let r = range
            return (1, MetricTape(range: Int(r.lowerBound)...Int(r.upperBound),
                                  pointsPerUnit: 3, minorStride: 5, labelStride: 30))
        case .calories:
            return (1, MetricTape(range: 1...2000, pointsPerUnit: 3, minorStride: 5, labelStride: 25))
        case .distance:
            switch distanceUnit {
            case .meters:
                let r = distanceUnit.range
                return (1, MetricTape(range: Int(r.lowerBound)...Int(r.upperBound),
                                      pointsPerUnit: 0.6, minorStride: 25, labelStride: 250))
            case .kilometers, .miles:
                let r = distanceUnit.range
                let lo = Int((r.lowerBound * 100).rounded())
                let hi = Int((r.upperBound * 100).rounded())
                return (0.01, MetricTape(range: lo...hi,
                                         pointsPerUnit: 3, minorStride: 5, labelStride: 25))
            }
        case .weight, .assistance, .reps, .height, .pace, .speed,
             .incline, .resistance, .power, .cadence, .rpe:
            return nil
        }
    }
}

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
    /// of the tiered wheel.
    ///
    /// The line (Dave, 2026-07-28, after the scrubber had run on time,
    /// distance and calories for a week): **a MEASURED quantity scrubs; an
    /// ENUMERATED scale wheels.** A tape is a ruler — it says "this value
    /// lives on a continuum, and here are its neighbours in both
    /// directions", which is exactly what a load, a count, a split, a
    /// speed, a grade and a wattage are. It also reaches every value
    /// between its marks, where the wheel could only ever land on its own
    /// grid (the 97 s / 3.14 mi / 137.5 lb problem). What stays on the
    /// wheel is the handful of metrics whose values ARE the list: machine
    /// resistance (30 numbered levels) and RPE (a subjective 1–10 rating).
    /// Rendering those as a ruler would claim a precision that isn't
    /// there, and a ten-stop ruler is worse than a ten-row wheel anyway.
    ///
    /// Exhaustive on purpose, like `isTimeSpan`/`step`/`range` — a new
    /// metric must DECIDE its picker, not silently fall to the wheel.
    var usesTapeScrubber: Bool {
        switch self {
        case .duration, .rest, .transition, .distance, .calories,
             .weight, .assistance, .reps, .height, .pace, .speed,
             .incline, .power, .cadence:
            true
        case .resistance, .rpe:
            false
        }
    }

    /// The scrubber tape for this metric plus the value one tape unit
    /// represents (its `quantum`), or nil for wheel metrics. Time spans,
    /// metered distance, reps and heights address whole units (1 s, 1 m,
    /// 1 rep, 1 in); the fractional metrics address the grain their gear
    /// actually holds — hundredths of a mile, half pounds and quarter
    /// kilos (finer than a microplate), tenths of a mph and of a percent
    /// grade. In every case the MARKS echo the wheel's old grain (25 m,
    /// 0.25 mi, 5 cal, 2.5 lb, 0.5 mph) so the tape reads familiar, while
    /// the value lands on any whole unit between them.
    ///
    /// `pointsPerUnit` is tuned so a viewport shows a workable span of the
    /// metric — roughly a plate's worth of weight, half a minute of split,
    /// a third of the rep range — with minor marks 10–30 pt apart and
    /// labels 50–90 pt apart, dense enough to read and sparse enough not
    /// to smear.
    func scrubberTape(weightUnit: WeightUnit = .lb, distanceUnit: DistanceUnit = .meters, paceReference: PaceReference? = nil) -> (quantum: Double, tape: MetricTape)? {
        switch self {
        case .duration, .rest, .transition:
            let r = range
            return (1, MetricTape(range: Int(r.lowerBound)...Int(r.upperBound),
                                  pointsPerUnit: 3, minorStride: 5, labelStride: 30))
        case .calories:
            let r = range
            return (1, MetricTape(range: Int(r.lowerBound)...Int(r.upperBound),
                                  pointsPerUnit: 3, minorStride: 5, labelStride: 25))
        case .distance:
            switch distanceUnit {
            // Whole meters / whole yards: both count in lengths, and
            // neither has a fractional value anyone states.
            case .meters, .yards:
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
        case .weight, .assistance:
            // Half a pound / a quarter kilo: FINER than a microplate, so
            // any pin stack or hand-recorded load is reachable, with the
            // marks on the wheel's old microplate grid (2.5 lb / 1.25 kg)
            // and a label every full plate-ish step (10 lb / 5 kg).
            let quantum = weightUnit == .kg ? 0.25 : 0.5
            let perValue = 1 / quantum
            let r = range(weightUnit: weightUnit)
            return (quantum, MetricTape(range: Int((r.lowerBound * perValue).rounded())...Int((r.upperBound * perValue).rounded()),
                                        pointsPerUnit: 3, minorStride: 5, labelStride: 20))
        case .reps:
            // Whole reps, one mark each — nobody does half a rep, and at
            // 10 pt apiece the whole working range is a flick away.
            let r = range
            return (1, MetricTape(range: Int(r.lowerBound)...Int(r.upperBound),
                                  pointsPerUnit: 10, minorStride: 1, labelStride: 5))
        case .height:
            // Whole inches / whole centimetres: a box or a step is a
            // stated height, never a fractional one.
            let r = range(weightUnit: weightUnit)
            let bounds = Int(r.lowerBound)...Int(r.upperBound)
            return weightUnit == .kg
                ? (1, MetricTape(range: bounds, pointsPerUnit: 4, minorStride: 5, labelStride: 20))
                : (1, MetricTape(range: bounds, pointsPerUnit: 8, minorStride: 1, labelStride: 6))
        case .pace:
            // Seconds, always — including on the road, where the wheel
            // could only offer 5 s steps and a 7:58 target was unpickable.
            // A SHORT reference gets the finer tape: an erg split and a
            // 100 m swim split are both dialed to the second over a range
            // a few minutes wide. The reference decides, not the unit —
            // a metric pool is denominated in meters and wants the fine
            // tape for /100m, not the erg's /500m span.
            let reference = paceReference ?? distanceUnit.defaultPaceReference
            let r = reference.range
            let bounds = Int(r.lowerBound)...Int(r.upperBound)
            return reference.wheelStep == 1
                ? (1, MetricTape(range: bounds, pointsPerUnit: 6, minorStride: 1, labelStride: 15))
                : (1, MetricTape(range: bounds, pointsPerUnit: 3, minorStride: 5, labelStride: 30))
        case .speed:
            // Tenths — a treadmill's own dial — marked every 0.5.
            let r = distanceUnit.speedRange
            return (0.1, MetricTape(range: Int((r.lowerBound * 10).rounded())...Int((r.upperBound * 10).rounded()),
                                    pointsPerUnit: 6, minorStride: 5, labelStride: 10))
        case .incline:
            // Tenths of a percent: the grade a treadmill actually holds,
            // marked every half percent and labeled every whole one.
            let r = range
            return (0.1, MetricTape(range: Int((r.lowerBound * 10).rounded())...Int((r.upperBound * 10).rounded()),
                                    pointsPerUnit: 6, minorStride: 5, labelStride: 10))
        case .power:
            // Whole watts over a 1500 W span — the wheel was 300 rows.
            let r = range
            return (1, MetricTape(range: Int(r.lowerBound)...Int(r.upperBound),
                                  pointsPerUnit: 2, minorStride: 5, labelStride: 25))
        case .cadence:
            // Whole steps/strokes per minute, marked every 5.
            let r = range
            return (1, MetricTape(range: Int(r.lowerBound)...Int(r.upperBound),
                                  pointsPerUnit: 4, minorStride: 5, labelStride: 20))
        case .resistance, .rpe:
            return nil
        }
    }
}

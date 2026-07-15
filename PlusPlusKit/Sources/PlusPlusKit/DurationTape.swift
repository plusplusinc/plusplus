import Foundation

/// The pure geometry behind the horizontal duration tape scrubber
/// (the iOS-27-timer-style ruler the app uses to pick durations and
/// rest with per-second precision): a linear seconds ↔ points mapping,
/// clamping, and the tick/label schedule. The SwiftUI layer draws what
/// this describes and owns nothing numeric, so the semantics are
/// Linux-testable — same split as `WorkoutMetric.wheelValues`.
public struct DurationTape: Equatable, Sendable {
    /// Whole seconds the tape spans, inclusive.
    public let range: ClosedRange<Int>
    /// Horizontal points per second of tape. 3 keeps one second a
    /// deliberate ~3 pt finger movement (precise but not twitchy) while
    /// a full hour stays a few flicks long.
    public let pointsPerSecond: Double

    public init(range: ClosedRange<Int>, pointsPerSecond: Double = 3) {
        self.range = range
        self.pointsPerSecond = max(pointsPerSecond, 0.1)
    }

    /// Total tape length in points (0 at `range.lowerBound`).
    public var length: Double {
        Double(range.upperBound - range.lowerBound) * pointsPerSecond
    }

    public func clamped(_ seconds: Int) -> Int {
        min(max(seconds, range.lowerBound), range.upperBound)
    }

    /// Tape offset (points from the lower bound) for a value.
    public func offset(for seconds: Int) -> Double {
        Double(clamped(seconds) - range.lowerBound) * pointsPerSecond
    }

    /// Nearest whole second for a tape offset; out-of-range offsets
    /// (rubber-band overshoot) clamp to the bounds.
    public func seconds(atOffset offset: Double) -> Int {
        clamped(range.lowerBound + Int((offset / pointsPerSecond).rounded()))
    }

    // MARK: - Ticks

    public struct Tick: Equatable, Sendable {
        public let seconds: Int
        /// Present on the 30 s and whole-minute marks ("30s", "1:00",
        /// "12:30"); nil on the plain 5 s marks. Bars render uniform
        /// (the iOS 27 tape look), so labeled-or-not is the only
        /// distinction the schedule carries.
        public let label: String?
    }

    /// Ticks whose tape offsets fall inside `window` (exactly — callers
    /// pad the window for edge drawing), ordered ascending. The
    /// visible-viewport query, so a 60-minute tape never enumerates all
    /// 720 marks per frame. Marks sit every 5 s; labels every 30 s.
    public func ticks(in window: ClosedRange<Double>) -> [Tick] {
        let lowExact = Double(range.lowerBound) + window.lowerBound / pointsPerSecond
        let highExact = Double(range.lowerBound) + window.upperBound / pointsPerSecond
        // First multiple of 5 inside both the window and the range…
        let firstInRange = Int((Double(range.lowerBound) / 5).rounded(.up)) * 5
        var s = max(firstInRange, Int((lowExact / 5).rounded(.up)) * 5)
        // …through the last multiple of 5 inside both.
        let highest = min(range.upperBound, Int((highExact / 5).rounded(.down)) * 5)
        var result: [Tick] = []
        while s <= highest {
            result.append(Tick(seconds: s, label: s % 30 == 0 ? Self.label(for: s) : nil))
            s += 5
        }
        return result
    }

    /// Compact clock-style duration text: "45s" under a minute, m:ss
    /// from there ("1:30", "12:00") — delegating the m:ss branch to
    /// `WorkoutMetric.formatted` so the clock format has one owner.
    /// The scrubber's readout AND every compact duration label in the
    /// app ("3×45s", "3×1:30") speak through this one helper.
    public static func label(for seconds: Int) -> String {
        seconds >= 60 ? WorkoutMetric.duration.formatted(Double(seconds)) : "\(seconds)s"
    }
}

public extension WorkoutMetric {
    /// True for metrics that ARE a span of time (duration targets and
    /// rest) — the ones the app picks on the tape scrubber instead of a
    /// wheel. Pace is m:ss too but is a rate, not a span. Exhaustive on
    /// purpose, like `step`/`range`/`wheelValues`: a new metric must
    /// DECIDE its picker, not silently fall to the wheel.
    var isTimeSpan: Bool {
        switch self {
        case .duration, .rest:
            true
        case .weight, .assistance, .reps, .height, .distance, .calories,
             .pace, .speed, .incline, .resistance, .power, .cadence, .rpe:
            false
        }
    }
}

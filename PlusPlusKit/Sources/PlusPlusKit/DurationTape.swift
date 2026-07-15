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

    public enum TickWeight: Equatable, Sendable {
        /// Unlabeled 5 s marks.
        case minor
        /// Labeled 30 s midpoints.
        case medium
        /// Labeled whole minutes.
        case major
    }

    public struct Tick: Equatable, Sendable {
        public let seconds: Int
        public let weight: TickWeight
        /// Present on medium/major ticks ("30s", "1:00", "12:30").
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
            let weight: TickWeight = s % 60 == 0 ? .major : (s % 30 == 0 ? .medium : .minor)
            result.append(Tick(
                seconds: s,
                weight: weight,
                label: weight == .minor ? nil : Self.label(for: s)
            ))
            s += 5
        }
        return result
    }

    /// Compact clock-style tape text: "45s" under a minute, m:ss from
    /// there ("1:30", "12:00"). Also the scrubber's big readout format.
    public static func label(for seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

public extension WorkoutMetric {
    /// True for metrics that ARE a span of time (duration targets and
    /// rest) — the ones the app picks on the tape scrubber instead of a
    /// wheel. Pace is m:ss too but is a rate, not a span.
    var isTimeSpan: Bool {
        self == .duration || self == .rest
    }
}

import Foundation

/// Compact clock-style duration text, plus the metric classification the
/// scrubber and its readout key on. The tape GEOMETRY moved to
/// `MetricTape` (2026-07-19) when the scrubber generalized past time to
/// cover distance and calories; this namespace keeps the duration label
/// formatter — used app-wide for "3×45s" style text — so the clock format
/// still has one owner.
public enum DurationTape {
    /// Compact clock-style duration text: "45s" under a minute, m:ss from
    /// there ("1:30", "12:00") — delegating the m:ss branch to
    /// `WorkoutMetric.formatted` so the clock format has one owner. The
    /// scrubber's time-span readout AND every compact duration label in the
    /// app ("3×45s", "3×1:30") speak through this one helper.
    public static func label(for seconds: Int) -> String {
        seconds >= 60 ? WorkoutMetric.duration.formatted(Double(seconds)) : "\(seconds)s"
    }
}

public extension WorkoutMetric {
    /// True for metrics that ARE a span of time (duration targets and rest).
    /// Narrower than `usesTapeScrubber` (which also covers distance and
    /// calories): a time span renders its scrubber readout as clock text
    /// (m:ss) rather than a number plus a unit. Pace is m:ss too but is a
    /// rate, not a span. Exhaustive on purpose, like `step`/`range` — a new
    /// metric must decide.
    var isTimeSpan: Bool {
        switch self {
        case .duration, .rest, .transition:
            true
        case .weight, .assistance, .reps, .height, .distance, .calories,
             .pace, .speed, .incline, .resistance, .power, .cadence, .rpe:
            false
        }
    }
}

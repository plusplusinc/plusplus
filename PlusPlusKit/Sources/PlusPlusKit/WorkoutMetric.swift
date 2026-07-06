import Foundation

/// The editable quantities on a WorkoutExercise. Pure value logic —
/// stepping, clamping, wheel values, display formatting — lives here so it
/// can be unit tested without a view or a ModelContainer, and used by the
/// CLI on non-Apple platforms.
public enum WorkoutMetric: Sendable {
    case weight
    case reps
    case duration
    case rest

    public var label: String {
        switch self {
        case .weight: "Weight"
        case .reps: "Reps"
        case .duration: "Duration"
        case .rest: "Rest"
        }
    }

    public var unit: String {
        switch self {
        case .weight: "lb"
        case .reps: "reps"
        case .duration: "sec"
        case .rest: "sec"
        }
    }

    /// Increment applied by the stepper's plus/minus buttons.
    public var step: Double {
        switch self {
        case .weight: 5
        case .reps: 1
        case .duration: 15
        case .rest: 15
        }
    }

    /// Granularity of the wheel picker — finer than the stepper for weight
    /// so microplate loads (2.5 lb) stay reachable. Duration uses tiered
    /// granularity instead (see `wheelValues`).
    public var wheelStep: Double {
        switch self {
        case .weight: 2.5
        case .reps: 1
        case .duration: 5
        case .rest: 15
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .weight: 0...1000
        case .reps: 1...100
        case .duration: 5...3600
        case .rest: 15...600
        }
    }

    /// Starting point when a value is first set from empty.
    public var defaultValue: Double {
        switch self {
        case .weight: 45
        case .reps: 10
        case .duration: 30
        case .rest: 90
        }
    }

    public func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Stepping from nil lands on `defaultValue` rather than stepping from zero.
    public func incremented(_ value: Double?) -> Double {
        guard let value else { return defaultValue }
        return clamped(value + step)
    }

    public func decremented(_ value: Double?) -> Double {
        guard let value else { return defaultValue }
        return clamped(value - step)
    }

    /// Duration covers a full hour, so its wheel coarsens as values grow:
    /// 5 s steps for short holds, 15 s steps to ten minutes, then whole
    /// minutes. A uniform 5 s stride to 3600 would be a 720-row wheel.
    public var wheelValues: [Double] {
        switch self {
        case .duration:
            var values = Array(stride(from: 5.0, to: 120, by: 5))
            values += Array(stride(from: 120.0, to: 600, by: 15))
            values += Array(stride(from: 600.0, through: 3600, by: 60))
            return values
        case .weight, .reps, .rest:
            return Array(stride(from: range.lowerBound, through: range.upperBound, by: wheelStep))
        }
    }

    /// Snaps an arbitrary stored value onto the wheel so the picker has a
    /// valid selection; nil lands on `defaultValue`.
    public func nearestWheelValue(to value: Double?) -> Double {
        guard let value else { return defaultValue }
        let bounded = clamped(value)
        return wheelValues.min { abs($0 - bounded) < abs($1 - bounded) } ?? defaultValue
    }

    /// Whole numbers render without a decimal; fractional weights keep one
    /// place. Durations of a minute or more render as m:ss ("25:00", not
    /// "1500"), which needs no unit suffix — see `unit(for:)`.
    public func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if self == .duration, value >= 60 {
            let total = Int(value.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// Unit suffix appropriate for a specific rendered value. Empty when
    /// `formatted` already carries the units (m:ss durations).
    public func unit(for value: Double?) -> String {
        if self == .duration, let value, value >= 60 { return "" }
        return unit
    }

    /// Value and unit as one display string: "45 sec", "25:00", "135 lb".
    public func displayText(_ value: Double?) -> String {
        let suffix = unit(for: value)
        return suffix.isEmpty ? formatted(value) : "\(formatted(value)) \(suffix)"
    }
}

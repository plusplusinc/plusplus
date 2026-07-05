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
    /// so microplate loads (2.5 lb) stay reachable.
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
        case .duration: 5...900
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

    public var wheelValues: [Double] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: wheelStep))
    }

    /// Snaps an arbitrary stored value onto the wheel so the picker has a
    /// valid selection; nil lands on `defaultValue`.
    public func nearestWheelValue(to value: Double?) -> Double {
        guard let value else { return defaultValue }
        let bounded = clamped(value)
        let steps = ((bounded - range.lowerBound) / wheelStep).rounded()
        return range.lowerBound + steps * wheelStep
    }

    /// Whole numbers render without a decimal; fractional weights keep one place.
    public func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

import Foundation

/// The editable quantities on a RoutineExercise. Pure value logic —
/// stepping, clamping, wheel values, display formatting — lives here so it
/// can be unit tested without a view or a ModelContainer, and used by the
/// CLI on non-Apple platforms.
///
/// The vocabulary is CURATED, not user-defined: every case carries owned,
/// tested semantics (step, range, format, improvement direction), and an
/// exercise's MetricProfile picks which of them it tracks. Raw values are
/// the stable identity used by profiles, stored value bags, and the
/// interchange format — never rename one.
public enum WorkoutMetric: String, Codable, CaseIterable, Sendable, Identifiable {
    // Declaration order IS the canonical display order (MetricProfile
    // normalizes to it): loads first, then work quantities, then the
    // machine-dial facts, then subjective rating. `rest` and `transition`
    // are block configuration, not tracked metrics — they never join a
    // profile (`isBlockConfiguration`).
    case weight
    case assistance
    case reps
    case height
    case distance
    case calories
    case duration
    case pace
    case speed
    case incline
    case resistance
    case power
    case cadence
    case rpe
    case rest
    /// Pause when the session moves to a DIFFERENT exercise or block —
    /// just enough to switch stations (#369). Rest covers a new round of
    /// the same block. 0 means no countdown at all.
    case transition

    /// Which direction means progress — drives diff celebration. `.down`
    /// metrics improve by shrinking (a faster split, less assistance);
    /// `.neutral` metrics are machine settings or subjective ratings that
    /// never enter the increment story (anti-shame: facts, not judgment).
    public enum ImprovementDirection: Sendable {
        case up, down, neutral
    }

    public var id: String { rawValue }

    /// Block configuration, not a tracked quantity: rest and transition
    /// shape the pause after a set. They never join a MetricProfile, stay
    /// out of the metric pickers, and may not ride an extras dictionary.
    public var isBlockConfiguration: Bool {
        self == .rest || self == .transition
    }

    public var improvementDirection: ImprovementDirection {
        switch self {
        case .weight, .reps, .duration, .distance, .power, .calories, .height: .up
        case .pace, .assistance: .down
        case .speed, .incline, .resistance, .cadence, .rpe, .rest, .transition: .neutral
        }
    }

    /// Metrics that can DRIVE a set — define what "doing the work" means.
    /// A profile must contain at least one; priority (reps > distance >
    /// calories > duration) resolves the execution mode when several have
    /// targets.
    public static let workMetrics: [WorkoutMetric] = [.reps, .distance, .calories, .duration]

    public var isWorkMetric: Bool { Self.workMetrics.contains(self) }

    public var label: String {
        switch self {
        case .weight: "Weight"
        case .assistance: "Assist"
        case .reps: "Reps"
        case .height: "Height"
        case .distance: "Distance"
        case .calories: "Calories"
        case .duration: "Duration"
        case .pace: "Pace"
        case .speed: "Speed"
        case .incline: "Incline"
        case .resistance: "Resistance"
        case .power: "Power"
        case .cadence: "Cadence"
        case .rpe: "RPE"
        case .rest: "Rest"
        case .transition: "Transition"
        }
    }

    public var unit: String {
        unit(weightUnit: .lb, distanceUnit: .meters)
    }

    private func unit(weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> String {
        switch self {
        case .weight, .assistance: weightUnit.symbol
        case .reps: "reps"
        case .height: weightUnit == .kg ? "cm" : "in"
        case .distance: distanceUnit.symbol
        case .calories: "cal"
        case .duration, .rest, .transition: "sec"
        case .pace: distanceUnit.paceLabel
        case .speed: distanceUnit.speedLabel
        case .incline: "%"
        case .resistance: "lvl"
        case .power: "W"
        case .cadence: "/min"
        case .rpe: ""
        }
    }

    /// Increment applied by the stepper's plus/minus buttons.
    public var step: Double {
        step(weightUnit: .lb, distanceUnit: .meters)
    }

    public func step(weightUnit: WeightUnit, distanceUnit: DistanceUnit = .meters) -> Double {
        switch self {
        case .weight, .assistance: weightUnit.step
        case .reps: 1
        case .height: weightUnit == .kg ? 5 : 1
        case .distance: distanceUnit.step
        case .calories: 5
        case .duration: 15
        case .rest: 15
        // Finer than rest: transitions live in the 0–60 s range, where a
        // 15 s stride would skip every value Dave actually wants.
        case .transition: 5
        case .pace: 5
        case .speed: 0.5
        case .incline: 0.5
        case .resistance: 1
        case .power: 5
        case .cadence: 5
        case .rpe: 0.5
        }
    }

    /// Granularity of the wheel picker — finer than the stepper for weight
    /// so microplate loads (2.5 lb) stay reachable. Duration uses tiered
    /// granularity instead (see `wheelValues`).
    public var wheelStep: Double {
        wheelStep(weightUnit: .lb, distanceUnit: .meters)
    }

    private func wheelStep(weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> Double {
        switch self {
        case .weight, .assistance: weightUnit.wheelStep
        case .reps: 1
        case .height: weightUnit == .kg ? 5 : 1
        case .distance: distanceUnit.wheelStep
        case .calories: 1
        case .duration: 5
        case .rest: 15
        case .transition: 5
        case .pace: distanceUnit.paceWheelStep
        case .speed: 0.5
        case .incline: 0.5
        case .resistance: 1
        case .power: 5
        case .cadence: 1
        case .rpe: 0.5
        }
    }

    public var range: ClosedRange<Double> {
        range(weightUnit: .lb, distanceUnit: .meters)
    }

    private func range(weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> ClosedRange<Double> {
        switch self {
        case .weight: 0...1000
        case .assistance: 0...500
        case .reps: 1...100
        case .height: weightUnit == .kg ? 5...180 : 1...72
        case .distance: distanceUnit.range
        case .calories: 1...2000
        case .duration: 5...3600
        case .rest: 15...600
        // 0 is legal and means "no countdown" — back-to-back stations.
        case .transition: 0...600
        case .pace: distanceUnit.paceRange
        case .speed: distanceUnit.speedRange
        case .incline: 0...15
        case .resistance: 1...30
        case .power: 5...1500
        case .cadence: 10...220
        case .rpe: 1...10
        }
    }

    /// Starting point when a value is first set from empty.
    public var defaultValue: Double {
        defaultValue(weightUnit: .lb, distanceUnit: .meters)
    }

    public func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func clamped(_ value: Double, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> Double {
        let range = range(weightUnit: weightUnit, distanceUnit: distanceUnit)
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Unit-aware value semantics
    // Weight and assistance are denominated in a settable unit (WeightUnit);
    // distance, pace, and speed in a per-exercise DistanceUnit; height rides
    // WeightUnit as its metric-vs-imperial signal (kg thinks in cm). Both
    // parameters default (.lb, .meters) so unit-indifferent callers and
    // pre-units code read unchanged.

    public func defaultValue(weightUnit: WeightUnit, distanceUnit: DistanceUnit = .meters) -> Double {
        switch self {
        case .weight: weightUnit.defaultValue
        case .assistance: weightUnit.defaultValue
        case .reps: 10
        case .height: weightUnit == .kg ? 50 : 20
        case .distance: distanceUnit.defaultValue
        case .calories: 15
        case .duration: 30
        // 45, not 90 (#369): with transitions carved out, rest no longer
        // has to cover station switches. Existing routines keep their
        // stored value; this is the prescription for NEW ones.
        case .rest: 45
        case .transition: 15
        case .pace: distanceUnit.paceDefault
        case .speed: distanceUnit.speedDefault
        case .incline: 1
        case .resistance: 5
        case .power: 100
        case .cadence: 60
        case .rpe: 8
        }
    }

    /// Stepping from nil lands on `defaultValue` rather than stepping from zero.
    /// `stepOverride` replaces the unit step when set — per-equipment
    /// increments (a microplate barbell steps 2.5, a pin stack 10)
    /// without touching wheel granularity or defaults.
    public func incremented(_ value: Double?, weightUnit: WeightUnit = .lb, distanceUnit: DistanceUnit = .meters, stepOverride: Double? = nil) -> Double {
        guard let value else { return defaultValue(weightUnit: weightUnit, distanceUnit: distanceUnit) }
        return clamped(value + (stepOverride ?? step(weightUnit: weightUnit, distanceUnit: distanceUnit)), weightUnit: weightUnit, distanceUnit: distanceUnit)
    }

    public func decremented(_ value: Double?, weightUnit: WeightUnit = .lb, distanceUnit: DistanceUnit = .meters, stepOverride: Double? = nil) -> Double {
        guard let value else { return defaultValue(weightUnit: weightUnit, distanceUnit: distanceUnit) }
        return clamped(value - (stepOverride ?? step(weightUnit: weightUnit, distanceUnit: distanceUnit)), weightUnit: weightUnit, distanceUnit: distanceUnit)
    }

    /// Duration covers a full hour, so its wheel coarsens as values grow:
    /// 5 s steps for short holds, 15 s steps to ten minutes, then whole
    /// minutes. A uniform 5 s stride to 3600 would be a 720-row wheel.
    public var wheelValues: [Double] {
        wheelValues(weightUnit: .lb)
    }

    public func wheelValues(weightUnit: WeightUnit, distanceUnit: DistanceUnit = .meters) -> [Double] {
        switch self {
        case .duration:
            var values = Array(stride(from: 5.0, to: 120, by: 5))
            values += Array(stride(from: 120.0, to: 600, by: 15))
            values += Array(stride(from: 600.0, through: 3600, by: 60))
            return values
        case .distance where distanceUnit == .meters:
            // Same tiering idea: 25 m fine grain to 1 km, 100 m to 10 km,
            // then 500 m — a uniform 25 m stride to 50 km would be a
            // 2000-row wheel.
            var values = Array(stride(from: 25.0, to: 1000, by: 25))
            values += Array(stride(from: 1000.0, to: 10000, by: 100))
            values += Array(stride(from: 10000.0, through: 50000, by: 500))
            return values
        default:
            let range = range(weightUnit: weightUnit, distanceUnit: distanceUnit)
            return Array(stride(
                from: range.lowerBound, through: range.upperBound,
                by: wheelStep(weightUnit: weightUnit, distanceUnit: distanceUnit)
            ))
        }
    }

    /// Snaps an arbitrary stored value onto the wheel so the picker has a
    /// valid selection; nil lands on `defaultValue`.
    public func nearestWheelValue(to value: Double?, weightUnit: WeightUnit = .lb, distanceUnit: DistanceUnit = .meters) -> Double {
        guard let value else { return defaultValue(weightUnit: weightUnit, distanceUnit: distanceUnit) }
        let bounded = clamped(value, weightUnit: weightUnit, distanceUnit: distanceUnit)
        return wheelValues(weightUnit: weightUnit, distanceUnit: distanceUnit).min { abs($0 - bounded) < abs($1 - bounded) }
            ?? defaultValue(weightUnit: weightUnit, distanceUnit: distanceUnit)
    }

    /// Whole numbers render without a decimal; fractional values keep the
    /// places they need ("137.5", "3.25"). Durations of a minute or more
    /// render as m:ss ("25:00", not "1500"), which needs no unit suffix —
    /// see `unit(for:)`. Pace is ALWAYS m:ss — splits read as clock time.
    public func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if self == .pace || (self == .duration && value >= 60) {
            let total = Int(value.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        if (value * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    /// Unit suffix appropriate for a specific rendered value. Empty when
    /// `formatted` already carries the units (m:ss durations) or the label
    /// does (RPE).
    public func unit(for value: Double?, weightUnit: WeightUnit = .lb, distanceUnit: DistanceUnit = .meters) -> String {
        if self == .duration, let value, value >= 60 { return "" }
        return unit(weightUnit: weightUnit, distanceUnit: distanceUnit)
    }

    /// Value and unit as one display string: "45 sec", "25:00", "135 lb",
    /// "2000 m", "2:05 /500m". Level-like metrics read label-first
    /// ("lvl 7", "RPE 8") and incline binds tight ("3%") — "7 lvl" isn't
    /// English.
    public func displayText(_ value: Double?, weightUnit: WeightUnit = .lb, distanceUnit: DistanceUnit = .meters) -> String {
        switch self {
        case .resistance:
            return "lvl \(formatted(value))"
        case .rpe:
            return "RPE \(formatted(value))"
        case .incline:
            return value == nil ? "—" : "\(formatted(value))%"
        default:
            let suffix = unit(for: value, weightUnit: weightUnit, distanceUnit: distanceUnit)
            return suffix.isEmpty ? formatted(value) : "\(formatted(value)) \(suffix)"
        }
    }
}

import Foundation

/// The diff engine behind the Today timeline (#111, Claude Design v3
/// handoff §4): how a staged routine differs from the last time each
/// exercise was performed, and how a committed session moved against
/// the one before it. Pure value logic — the app maps its SwiftData
/// models into these inputs.
public enum RoutineDiff {
    /// One exercise's staged targets.
    public struct Target: Equatable, Sendable {
        public var name: String
        public var isDuration: Bool
        public var weight: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        /// Tracked metrics beyond the classic three (distance, pace,
        /// power, calories…). Only the diffable ones participate; the
        /// rest are machine settings the diff ignores.
        public var extras: [WorkoutMetric: Double]
        /// What the extras' distance/pace numbers are denominated in.
        public var distanceUnit: DistanceUnit

        public init(name: String, isDuration: Bool = false, weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil, extras: [WorkoutMetric: Double] = [:], distanceUnit: DistanceUnit = .meters) {
            self.name = name
            self.isDuration = isDuration
            self.weight = weight
            self.reps = reps
            self.durationSeconds = durationSeconds
            self.extras = extras
            self.distanceUnit = distanceUnit
        }
    }

    /// How the same exercise went the last time it was completed —
    /// nil when it has never been performed.
    public struct Prior: Equatable, Sendable {
        public var weight: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        public var extras: [WorkoutMetric: Double]

        public init(weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil, extras: [WorkoutMetric: Double] = [:]) {
            self.weight = weight
            self.reps = reps
            self.durationSeconds = durationSeconds
            self.extras = extras
        }
    }

    /// The single delta an exercise contributes to the summary line.
    /// Improvements only (#246): a silenced weight decrease falls through
    /// to a reps increase — see `delta(target:prior:)` for the why.
    /// Pace improvements carry a NEGATIVE value (faster = smaller) but
    /// render as up-kind — the direction that means progress is the
    /// metric's, not the number's.
    public enum Delta: Equatable, Sendable {
        case new
        case unchanged
        case weight(Double)
        case reps(Int)
        case duration(Int)
        case distance(Double, DistanceUnit)
        case pace(Double, DistanceUnit)
        case calories(Double)
        case power(Double)

        public var isChange: Bool {
            switch self {
            case .unchanged: return false
            default: return true
            }
        }
    }

    /// The order improvements are looked for — the first that moved is
    /// the exercise's one delta. Weight beats reps (the v3 rule); for
    /// cardio, a faster pace is the sexiest increment, then more
    /// distance/calories/watts, then longer duration.
    static let diffPriority: [WorkoutMetric] = [.weight, .reps, .pace, .distance, .calories, .power, .duration]

    /// Deltas report IMPROVEMENTS only (#246): the prior is the last
    /// ACTUAL performance, so a plan sitting below it is the normal
    /// morning-after state when the user out-lifted the plan (weight
    /// carry-forward raises actuals, not routine targets) — rendering
    /// that as a minus made beating the plan read as a planned
    /// regression. Deliberate deloads are known to their author; the
    /// diff celebrates the direction that means progress (up for
    /// weight/reps/distance, DOWN for pace) and stays quiet otherwise
    /// (anti-shame). A silenced weight decrease falls through to a reps
    /// increase, so the up that exists still shows. Neutral-direction
    /// metrics (resistance, incline, speed…) are settings, not progress —
    /// they never produce a delta.
    public static func delta(target: Target, prior: Prior?) -> Delta {
        guard let prior else { return .new }
        for metric in diffPriority {
            let staged: Double?
            let last: Double?
            switch metric {
            case .weight:
                staged = target.weight
                last = prior.weight
            case .reps:
                staged = target.reps.map(Double.init)
                last = prior.reps.map(Double.init)
            case .duration:
                staged = target.durationSeconds.map(Double.init)
                last = prior.durationSeconds.map(Double.init)
            default:
                staged = target.extras[metric]
                last = prior.extras[metric]
            }
            guard let staged, let last else { continue }
            let improved = switch metric.improvementDirection {
            case .up: staged > last
            case .down: staged < last
            case .neutral: false
            }
            guard improved else { continue }
            switch metric {
            case .weight: return .weight(staged - last)
            case .reps: return .reps(Int(staged - last))
            case .duration: return .duration(Int(staged - last))
            case .distance: return .distance(staged - last, target.distanceUnit)
            case .pace: return .pace(staged - last, target.distanceUnit)
            case .calories: return .calories(staged - last)
            case .power: return .power(staged - last)
            default: continue
            }
        }
        return .unchanged
    }

    // MARK: - Summary line

    /// One colored run of the diff summary line. Direction is semantic —
    /// the palette decides rendering (up = data green, down = neutral
    /// gray per the anti-shame rules, new = info, unchanged = faint).
    public struct Segment: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case up, down, new, unchanged
        }

        public var kind: Kind
        public var text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Aggregates deltas (in routine order) into the collapsed summary:
    /// changed deltas first, then "n =" for the unchanged count; a diff
    /// with no changes at all collapses to one faint "=" (symbols only
    /// — words there start sounding like judgment, #246).
    public static func summary(deltas: [Delta], weightUnit: WeightUnit = .lb) -> [Segment] {
        var segments: [Segment] = []
        var unchanged = 0
        var newCount = 0
        for delta in deltas {
            switch delta {
            case .unchanged:
                unchanged += 1
            case .new:
                newCount += 1
            case .weight(let by):
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(by, unit: weightUnit.symbol)))
            case .reps(let by):
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(Double(by), unit: by == 1 || by == -1 ? "rep" : "reps")))
            case .duration(let by):
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(Double(by), unit: "sec")))
            case .distance(let by, let unit):
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(by, unit: unit.symbol)))
            case .pace(let by, let unit):
                // A negative pace delta IS the improvement — faster.
                // "−0:05 /500m" in up-green: kind speaks progress, the
                // sign speaks arithmetic.
                segments.append(Segment(kind: by < 0 ? .up : .down, text: signedPace(by, unit: unit)))
            case .calories(let by):
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(by, unit: "cal")))
            case .power(let by):
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(by, unit: "W")))
            }
        }
        if newCount > 0 {
            segments.append(Segment(kind: .new, text: newCount == 1 ? "1 new" : "\(newCount) new"))
        }
        if segments.isEmpty {
            return [Segment(kind: .unchanged, text: "=")]
        }
        if unchanged > 0 {
            segments.append(Segment(kind: .unchanged, text: "\(unchanged) ="))
        }
        return segments
    }

    /// "+5 lb", "−2.5 kg", "+2 reps" — the minus is a true minus sign.
    static func signed(_ value: Double, unit: String) -> String {
        let magnitude = abs(value)
        let text = magnitude.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(magnitude))
            : String(magnitude)
        return (value > 0 ? "+" : "−") + text + " " + unit
    }

    /// "−0:05 /500m" — pace deltas read as clock time like pace itself.
    static func signedPace(_ value: Double, unit: DistanceUnit) -> String {
        let total = Int(abs(value).rounded())
        let clock = String(format: "%d:%02d", total / 60, total % 60)
        return (value > 0 ? "+" : "−") + clock + " " + unit.paceLabel
    }

    // MARK: - Net chip (committed entries)

    /// Sum of POSITIVE per-exercise weight movements between two
    /// committed sessions of the same routine, keyed by exercise name
    /// (top completed set weight per exercise). Regressions don't
    /// subtract — deloads are intentional; the chip celebrates up only,
    /// and the caller hides it when the result is zero.
    public static func netWeightGain(current: [String: Double], previous: [String: Double]) -> Double {
        var gain = 0.0
        for (name, weight) in current {
            if let before = previous[name], weight > before {
                gain += weight - before
            }
        }
        return gain
    }
}

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

        public init(name: String, isDuration: Bool = false, weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil) {
            self.name = name
            self.isDuration = isDuration
            self.weight = weight
            self.reps = reps
            self.durationSeconds = durationSeconds
        }
    }

    /// How the same exercise went the last time it was completed —
    /// nil when it has never been performed.
    public struct Prior: Equatable, Sendable {
        public var weight: Double?
        public var reps: Int?
        public var durationSeconds: Int?

        public init(weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil) {
            self.weight = weight
            self.reps = reps
            self.durationSeconds = durationSeconds
        }
    }

    /// The single delta an exercise contributes to the summary line.
    /// When both weight and reps changed, weight wins (§4); the expanded
    /// row may show both.
    public enum Delta: Equatable, Sendable {
        case new
        case unchanged
        case weight(Double)
        case reps(Int)
        case duration(Int)

        public var isChange: Bool {
            switch self {
            case .unchanged: return false
            default: return true
            }
        }
    }

    /// Deltas report INCREASES only (#246): the prior is the last
    /// ACTUAL performance, so a plan sitting below it is the normal
    /// morning-after state when the user out-lifted the plan (weight
    /// carry-forward raises actuals, not routine targets) — rendering
    /// that as a minus made beating the plan read as a planned
    /// regression. Deliberate deloads are known to their author; the
    /// diff celebrates up and stays quiet otherwise (anti-shame).
    /// A silenced weight decrease falls through to a reps increase, so
    /// the up that exists still shows.
    public static func delta(target: Target, prior: Prior?) -> Delta {
        guard let prior else { return .new }
        if target.isDuration {
            if let staged = target.durationSeconds, let last = prior.durationSeconds, staged > last {
                return .duration(staged - last)
            }
            return .unchanged
        }
        if let staged = target.weight, let last = prior.weight, staged > last {
            return .weight(staged - last)
        }
        if let staged = target.reps, let last = prior.reps, staged > last {
            return .reps(staged - last)
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

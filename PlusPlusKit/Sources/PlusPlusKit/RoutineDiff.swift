import Foundation

/// The diff engine behind the Today timeline (#111, Claude Design v3
/// handoff §4): how a staged routine differs from the last time each
/// exercise was performed, and how a committed session moved against
/// the one before it. Pure value logic — the app maps its SwiftData
/// models into these inputs.
public enum RoutineDiff {
    /// A prescription field the diff can compare between the plan and the
    /// last performance: the block's set count, plus every tracked metric.
    ///
    /// Two things a routine exercise carries are deliberately absent,
    /// because a performance never records them as actuals. The block's
    /// REST rides `SetLog.restSecondsOverride`, which snapshots the
    /// target in force at start time, not the rest actually taken; the
    /// HEART-RATE TARGET rides `targetHeartRateData` the same way. Both
    /// can change on a routine, but there is no actual to diff them
    /// against, so they belong to a target-versus-target comparison this
    /// type does not model. Adding them here would only produce fields
    /// that can never differ.
    public enum Field: Hashable, Sendable {
        case sets
        case metric(WorkoutMetric)
    }

    /// One exercise's staged targets — the whole prescription, so a
    /// caller can render it as well as diff it.
    public struct Target: Equatable, Sendable {
        public var name: String
        public var isDuration: Bool
        /// Rounds of this block. A block belongs to the group rather than
        /// the exercise, but it is part of what the exercise asks for:
        /// 3×8 becoming 4×8 is a real increase that used to read as
        /// unchanged, because nothing here knew about it.
        public var sets: Int?
        public var weight: Double?
        public var reps: Int?
        /// Top of a target rep RANGE ("8–10"); nil means `reps` is a
        /// single number. An actual is always one count, so this never
        /// diffs on its own — it widens `reps` into a band that a prior
        /// actual can sit inside (see `changedFields`).
        public var repsUpper: Int?
        public var durationSeconds: Int?
        /// Tracked metrics beyond the classic three (distance, pace,
        /// power, calories…). `delta` reports only the ones with a
        /// direction of progress; `changedFields` reports the neutral
        /// machine settings too, since a changed setting is still a
        /// changed prescription.
        public var extras: [WorkoutMetric: Double]
        /// What the extras' distance/pace numbers are denominated in.
        public var distanceUnit: DistanceUnit

        public init(name: String, isDuration: Bool = false, sets: Int? = nil, weight: Double? = nil, reps: Int? = nil, repsUpper: Int? = nil, durationSeconds: Int? = nil, extras: [WorkoutMetric: Double] = [:], distanceUnit: DistanceUnit = .meters) {
            self.name = name
            self.isDuration = isDuration
            self.sets = sets
            self.weight = weight
            self.reps = reps
            self.repsUpper = repsUpper
            self.durationSeconds = durationSeconds
            self.extras = extras
            self.distanceUnit = distanceUnit
        }
    }

    /// How the same exercise went the last time it was completed —
    /// nil when it has never been performed.
    public struct Prior: Equatable, Sendable {
        /// Sets actually COMPLETED, which is not always the number
        /// planned: three of four finished reads 3, honestly.
        public var sets: Int?
        public var weight: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        public var extras: [WorkoutMetric: Double]

        public init(sets: Int? = nil, weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil, extras: [WorkoutMetric: Double] = [:]) {
            self.sets = sets
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
        case sets(Int)
        case weight(Double)
        case reps(Int)
        case duration(Int)
        case distance(Double, DistanceUnit)
        case pace(Double, DistanceUnit)
        case calories(Double)
        case power(Double)
        /// Negative value = less assistance = the improvement.
        case assistance(Double)
        case height(Double)

        public var isChange: Bool {
            switch self {
            case .unchanged: return false
            default: return true
            }
        }
    }

    /// The order improvements are looked for — the first that moved is
    /// the exercise's one delta. Load beats reps (the v3 rule; a lighter
    /// assistance stack IS the load moving), then an added ROUND, which
    /// buys more volume than a couple of reps does, then reps, then the
    /// plyo box, then for cardio a faster pace is the sexiest increment,
    /// then more distance/calories/watts, then longer duration.
    static let diffPriority: [Field] = [
        .metric(.weight), .metric(.assistance), .sets, .metric(.reps), .metric(.height),
        .metric(.pace), .metric(.distance), .metric(.calories), .metric(.power), .metric(.duration),
    ]

    /// Whether a field moved in the direction that means progress. Sets
    /// go up like load; every metric follows its own
    /// `improvementDirection`, and the neutral ones (resistance, incline,
    /// speed, cadence, RPE) are settings rather than progress, so they
    /// never qualify.
    static func improves(_ field: Field, from last: Double, to staged: Double) -> Bool {
        switch field {
        case .sets:
            return staged > last
        case .metric(let metric):
            switch metric.improvementDirection {
            case .up: return staged > last
            case .down: return staged < last
            case .neutral: return false
            }
        }
    }

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
        for field in diffPriority {
            guard let staged = target.value(for: field),
                  let last = prior.value(for: field),
                  improves(field, from: last, to: staged)
            else { continue }
            switch field {
            case .sets: return .sets(Int(staged - last))
            case .metric(let metric):
                switch metric {
                case .weight: return .weight(staged - last)
                case .reps: return .reps(Int(staged - last))
                case .duration: return .duration(Int(staged - last))
                case .distance: return .distance(staged - last, target.distanceUnit)
                case .pace: return .pace(staged - last, target.distanceUnit)
                case .calories: return .calories(staged - last)
                case .power: return .power(staged - last)
                case .assistance: return .assistance(staged - last)
                case .height: return .height(staged - last)
                default: continue
                }
            }
        }
        return .unchanged
    }

    /// Every prescription field that DIFFERS from the last performance, in
    /// either direction — including the neutral-direction settings
    /// `delta` ignores (resistance, incline, speed, cadence, RPE), because
    /// a changed setting is still a changed prescription.
    ///
    /// Where `delta` answers "what progressed", picking one field, this
    /// answers "what is not the same", listing all of them. A display that
    /// shows the target beside the previous actual needs the second
    /// question: it has to mark every value that moved, not just the one
    /// worth celebrating.
    ///
    /// A field counts as changed when the two sides differ, or when
    /// exactly one carries a value. Both absent is not a change, and a nil
    /// `prior` returns an empty set — nothing is comparable against a
    /// performance that never happened, which `delta` already reports as
    /// `.new`.
    public static func changedFields(target: Target, prior: Prior?) -> Set<Field> {
        guard let prior else { return [] }
        var changed: Set<Field> = []
        if target.sets != prior.sets { changed.insert(.sets) }
        for metric in WorkoutMetric.allCases where !metric.isBlockConfiguration {
            let field = Field.metric(metric)
            switch (target.value(for: field), prior.value(for: field)) {
            case (nil, nil):
                continue
            case (let staged?, let last?):
                if metric == .reps {
                    // A rep RANGE is met by any count inside it: 8–10
                    // asked for and 9 done is not a change, while the
                    // same 9 against a 10–12 target is.
                    let upper = target.repsUpper.map(Double.init) ?? staged
                    if last < staged || last > upper { changed.insert(field) }
                } else if staged != last {
                    changed.insert(field)
                }
            default:
                changed.insert(field)
            }
        }
        return changed
    }

    // MARK: - Summary line

    /// One colored run of the diff summary line. Direction is semantic —
    /// the palette decides rendering (up = data green, down = neutral
    /// gray per the anti-shame rules, new = info). Unchanged deltas emit
    /// no segment at all (Dave, 2026-07-23: "=" and "n =" read as noise,
    /// nowhere renders them — superseding #246's faint "=").
    public struct Segment: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case up, down, new
        }

        public var kind: Kind
        public var text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Aggregates deltas (in routine order) into the collapsed summary:
    /// changed deltas in order, then the new-count. Unchanged deltas
    /// contribute NOTHING — no "=", no "n =" tail — so an all-unchanged
    /// diff summarizes as an empty array and callers simply omit the
    /// line (Dave, 2026-07-23, superseding #246's faint "=").
    public static func summary(deltas: [Delta], weightUnit: WeightUnit = .lb) -> [Segment] {
        var segments: [Segment] = []
        var newCount = 0
        for delta in deltas {
            switch delta {
            case .unchanged:
                break
            case .new:
                newCount += 1
            case .sets(let by):
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(Double(by), unit: abs(by) == 1 ? "set" : "sets")))
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
            case .assistance(let by):
                // Less assistance is the improvement: "−10 lb assist"
                // in up-green — kind speaks progress, the sign speaks
                // arithmetic (the pace rule).
                segments.append(Segment(kind: by < 0 ? .up : .down, text: signed(by, unit: "\(weightUnit.symbol) assist")))
            case .height(let by):
                // Height rides the weight unit (in/cm), like the metric.
                segments.append(Segment(kind: by > 0 ? .up : .down, text: signed(by, unit: weightUnit == .kg ? "cm" : "in")))
            }
        }
        if newCount > 0 {
            segments.append(Segment(kind: .new, text: newCount == 1 ? "1 new" : "\(newCount) new"))
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

// MARK: - Field access

/// One lookup per side, so `delta` and `changedFields` walk fields without
/// either of them restating where a value is stored — the columns
/// (weight/reps/duration) and the extras bag read the same way.
extension RoutineDiff.Target {
    public func value(for field: RoutineDiff.Field) -> Double? {
        switch field {
        case .sets:
            return sets.map(Double.init)
        case .metric(let metric):
            switch metric {
            case .weight: return weight
            case .reps: return reps.map(Double.init)
            case .duration: return durationSeconds.map(Double.init)
            default: return extras[metric]
            }
        }
    }
}

extension RoutineDiff.Prior {
    public func value(for field: RoutineDiff.Field) -> Double? {
        switch field {
        case .sets:
            return sets.map(Double.init)
        case .metric(let metric):
            switch metric {
            case .weight: return weight
            case .reps: return reps.map(Double.init)
            case .duration: return durationSeconds.map(Double.init)
            default: return extras[metric]
            }
        }
    }
}

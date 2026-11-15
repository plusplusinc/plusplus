import Foundation

// A row's values one part at a time, as its sheet shows them and steps them.

extension RoutineExercise {
    /// What a part is called: "Sets", "Reps" or "Time", "Weight".
    public func label(of part: PlanPart) -> String {
        switch part {
        case .sets: "Sets"
        case .target:
            if case .time = plan.target {
                "Time"
            } else {
                "Reps"
            }
        case .weight: "Weight"
        case .rest: "Rest"
        }
    }

    /// A part's value under its label, saying what it is for as the row does: "3", "10 per
    /// side", "2:30 min", "20 lb/side".
    public func value(of part: PlanPart, locale: Locale = .current) -> String {
        switch part {
        case .sets:
            plan.sets.formatted(.number.locale(locale))
        case .target:
            qualified(plan.target.number(locale: locale), .target)
        case .weight:
            qualified(plan.weight?.text(locale: locale) ?? "", .weight)
        case .rest:
            Self.restText(rest, locale: locale)
        }
    }

    /// A part's value as a number, the one its text reads: sets, reps or seconds, the weight in
    /// its unit, the rest in seconds. A row's digits roll up or down by it.
    public func amount(of part: PlanPart) -> Double {
        switch part {
        case .sets: Double(plan.sets)
        case .target:
            switch plan.target {
            case let .reps(reps): Double(reps)
            case let .time(seconds): Double(seconds)
            }
        case .weight: plan.weight?.amount ?? 0
        case .rest: Double(rest)
        }
    }

    /// The weight as its open row reads it while a ruler sets it, always one decimal or two,
    /// "25.0 lb", "27.5 lb/side", so its digits keep their count as the ruler turns.
    public func dialedWeight(locale: Locale = .current) -> String {
        qualified(plan.weight?.text(locale: locale, decimals: 1 ... 2) ?? "", .weight)
    }

    /// A part's value in words, for VoiceOver: "3 sets", "10 reps per side", "20 pounds per
    /// side".
    public func spokenValue(of part: PlanPart, locale: Locale = .current) -> String {
        switch part {
        case .sets:
            counted(plan.sets, "set", "sets", locale: locale)
        case .target:
            qualified(plan.target.spokenText(locale: locale), .target)
        case .weight:
            qualified(plan.weight?.spokenText(locale: locale) ?? "", .weight, spoken: true)
        case .rest:
            Self.spokenRest(rest, locale: locale)
        }
    }

    /// "None", "30s", "2m 30s".
    static func restText(_ seconds: Int, locale: Locale) -> String {
        seconds == 0 ? "None" : TimeText.text(seconds: seconds, locale: locale)
    }

    /// "None", "30 seconds", "2 minutes 30 seconds".
    static func spokenRest(_ seconds: Int, locale: Locale) -> String {
        seconds == 0 ? "None" : TimeText.spoken(seconds: seconds, locale: locale)
    }

    /// Moves a part one step up (`direction` 1) or down (-1): a set or a rep at a time, a time
    /// 5 s at a time, a weight its load's step in its unit, and a rest to the next 15 s mark. It
    /// stops at the limits a plan is stored within, a time at 5 s, a weight at one step, a bar's
    /// at the empty bar, and a rest at none.
    public mutating func step(_ part: PlanPart, by direction: Int) {
        if let stepped = stepped(part, by: direction) {
            plan = stepped
        }
    }

    /// Whether a part can move a step that way, or is at its limit.
    public func canStep(_ part: PlanPart, by direction: Int) -> Bool {
        stepped(part, by: direction) != nil
    }

    private func stepped(_ part: PlanPart, by direction: Int) -> ExercisePlan? {
        var plan = plan
        switch part {
        case .sets:
            guard let sets = plan.sets.stepped(by: direction, within: PlanLimits.sets)
            else { return nil }
            plan.sets = sets
        case .target:
            switch plan.target {
            case let .reps(reps):
                guard let reps = reps.stepped(by: direction, within: PlanLimits.reps)
                else { return nil }
                plan.target = .reps(reps)
            case let .time(seconds):
                let mark = seconds.nextMark(of: Self.timeStep, by: direction)
                guard let seconds = seconds.stepped(by: mark - seconds, within: Self.timeRange)
                else { return nil }
                plan.target = .time(seconds: seconds)
            }
        case .weight:
            guard var weight = plan.weight, let load = exercise.load, let range = weightRange
            else { return nil }
            let step = load.step(in: weight.unit)
            let mark = weight.amount.nextMark(of: step, by: direction)
            guard let amount = weight.amount.stepped(by: mark - weight.amount, within: range)
            else { return nil }
            weight.amount = amount
            plan.weight = weight
        case .rest:
            guard let rest = rest.steppedRest(by: direction) else { return nil }
            plan.rest = .byHand(rest)
        }
        return plan
    }

    /// A timed set's step, and its ruler's tick.
    public static let timeStep = 5

    /// The times its stepper and ruler move within, in seconds: one step up to the last step
    /// under the limit a plan is stored within, 5 s to 99:55.
    public static let timeRange = timeStep ... PlanLimits.seconds.upperBound / timeStep * timeStep

    /// The rests a row's or a superset's stepper and ruler move within, in seconds, none to
    /// 10 min, and their step.
    public static let restRange = PlanLimits.rest
    public static let restStep = PlanLimits.restStep

    /// Sets a timed set's time, held to `timeRange`; a set of reps keeps its reps.
    public mutating func setTime(_ seconds: Int) {
        guard case .time = plan.target else { return }
        plan.target = .time(seconds: min(
            max(seconds, Self.timeRange.lowerBound),
            Self.timeRange.upperBound,
        ))
    }

    /// Sets the rest by hand, as a step does, which turns Auto off; held to `restRange`.
    public mutating func setRest(_ seconds: Int) {
        plan.rest = .byHand(Self.heldRest(seconds))
    }

    static func heldRest(_ seconds: Int) -> Int {
        min(max(seconds, restRange.lowerBound), restRange.upperBound)
    }

    /// A time as an open row reads it while a ruler sets it, both units always, "0m 45s",
    /// "1m 0s", "0m 0s", so its parts keep their place as it turns, as a weight keeps its ".0".
    public static func dialedTime(_ seconds: Int, locale: Locale = .current) -> String {
        TimeText.bothUnits(seconds: seconds, locale: locale)
    }

    /// A time as a ruler's label reads it, as a value does: "30s", "1m", "1m 30s".
    public static func rulerTime(_ seconds: Int, locale: Locale = .current) -> String {
        TimeText.text(seconds: seconds, locale: locale)
    }

    /// A time as a sentence reads it, "1 min 35 sec", where a value reads "1m 35s".
    public static func sentenceTime(_ seconds: Int, locale: Locale = .current) -> String {
        TimeText.inSentence(seconds: seconds, locale: locale)
    }

    /// A part's value as its open row reads it while a ruler sets it: a weight with one decimal,
    /// a time or a rest in `dialedTime`'s shape; reps and sets as they read anywhere.
    public func dialedValue(of part: PlanPart, locale: Locale = .current) -> String {
        switch part {
        case .weight: dialedWeight(locale: locale)
        case .target:
            if case let .time(seconds) = plan.target {
                qualified(Self.dialedTime(seconds, locale: locale), .target)
            } else {
                value(of: part, locale: locale)
            }
        case .rest: Self.dialedTime(rest, locale: locale)
        case .sets: value(of: part, locale: locale)
        }
    }

    /// The weights its stepper moves within, in the weight's unit: one step up to the limit a
    /// plan is stored within, a bar's from the empty bar; nil without a weight.
    public var weightRange: ClosedRange<Double>? {
        guard let weight = shownWeight, let load = exercise.load else { return nil }
        let lightest = load == .bar ? Weight.emptyBar(weight.unit).amount : load
            .step(in: weight.unit)
        return lightest ... PlanLimits.weight.upperBound
    }

    /// Sets the weight to an amount in its own unit, held to `weightRange`.
    public mutating func setWeight(_ amount: Double) {
        guard let range = weightRange else { return }
        plan.weight?.amount = min(max(amount, range.lowerBound), range.upperBound)
    }

    /// The weight's number alone, as it is typed, "27.5" with no grouping, and what follows it
    /// in the row's value, " lb/side"; nil without a weight.
    public func weightEntry(locale: Locale = .current) -> (number: String, unit: String)? {
        guard let weight = shownWeight else { return nil }
        let number = weight.amount.formatted(
            .number.precision(.fractionLength(0 ... 2)).grouping(.never).locale(locale),
        )
        return (number, qualified(noBreakSpace + weight.unit.rawValue, .weight))
    }

    /// Sets the weight to a typed number in its own unit, to two decimals, when it reads as one
    /// within the limits a plan is stored within; otherwise keeps it. Whether it took.
    @discardableResult
    public mutating func setWeight(typed text: String, locale: Locale = .current) -> Bool {
        guard shownWeight != nil, let amount = Self.typedAmount(text, locale: locale),
              PlanLimits.weight.contains(amount)
        else { return false }
        plan.weight?.amount = amount
        return true
    }

    /// A typed number read in the locale, its decimal separator either one, rounded to two
    /// decimals.
    public static func typedAmount(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let separator = locale.decimalSeparator ?? "."
        let normalized = trimmed
            .replacingOccurrences(of: separator, with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              normalized.count(where: { $0 == "." }) <= 1,
              let amount = Double(normalized), amount.isFinite
        else { return nil }
        return (amount * 100).rounded() / 100
    }
}

private let noBreakSpace = "\u{00A0}"

extension Double {
    /// The next multiple of `step` up (`direction` 1) or down (-1), so a weight off the marks,
    /// 27.5 in 5 lb steps, lands on one (30 or 25) and moves a step from there.
    func nextMark(of step: Double, by direction: Int) -> Double {
        let marks = self / step
        let tolerance = 1e-9
        let index = direction > 0 ? (marks + tolerance).rounded(.down) + 1
            : (marks - tolerance).rounded(.up) - 1
        return index * step
    }
}

extension Int {
    /// The next multiple of `step` up (`direction` 1) or down (-1), so a time off the marks,
    /// 32 s in 5 s steps, lands on one (35 or 30) and moves a step from there.
    func nextMark(of step: Int, by direction: Int) -> Int {
        direction > 0 ? (self / step + 1) * step : (self - 1) / step * step
    }

    /// A rest moved to the next 15 s mark up (`direction` 1) or down (-1), so a rest off the
    /// marks, a timed set's own time, lands on one (50 s goes to 60 or 45) and moves by 15 s from
    /// there; held to a rest's limits, nil at the end it moves toward.
    func steppedRest(by direction: Int) -> Int? {
        let mark = nextMark(of: PlanLimits.restStep, by: direction)
        return stepped(by: mark - self, within: PlanLimits.rest)
    }
}

extension Comparable where Self: AdditiveArithmetic {
    /// The value moved by `delta` and held within `range`, or nil if it's already at the end
    /// `delta` moves toward, so a step never moves the wrong way.
    func stepped(by delta: Self, within range: ClosedRange<Self>) -> Self? {
        let canMove = delta > .zero ? self < range.upperBound
            : delta < .zero && self > range.lowerBound
        return canMove ? min(max(self + delta, range.lowerBound), range.upperBound) : nil
    }
}

extension SetTarget {
    /// The number alone for reps, which its label names, and a time with its unit: "10", "30 s".
    func number(locale: Locale) -> String {
        switch self {
        case let .reps(reps): reps.formatted(.number.locale(locale))
        case let .time(seconds): TimeText.text(seconds: seconds, locale: locale)
        }
    }
}

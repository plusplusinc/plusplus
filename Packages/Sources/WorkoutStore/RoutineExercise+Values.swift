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

    /// "None", "30 s", "2:30 min".
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
                let range = Self.timeStep ... PlanLimits.seconds.upperBound
                guard let seconds = seconds.stepped(by: direction * Self.timeStep, within: range)
                else { return nil }
                plan.target = .time(seconds: seconds)
            }
        case .weight:
            guard var weight = plan.weight, let load = exercise.load else { return nil }
            let step = load.step(in: weight.unit)
            let lightest = load == .bar ? Weight.emptyBar(weight.unit).amount : step
            let range = lightest ... PlanLimits.weight.upperBound
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

    private static let timeStep = 5

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
        guard !normalized.isEmpty, normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
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
    /// A rest moved to the next 15 s mark up (`direction` 1) or down (-1), so a rest off the
    /// marks, a timed set's own time, lands on one (50 s goes to 60 or 45) and moves by 15 s from
    /// there; held to a rest's limits, nil at the end it moves toward.
    func steppedRest(by direction: Int) -> Int? {
        let step = PlanLimits.restStep
        let mark = direction > 0 ? (self / step + 1) * step : (self - 1) / step * step
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

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
        }
    }

    /// Moves a part one step up (`direction` 1) or down (-1): a set or a rep at a time, a time
    /// 5 s at a time, a weight its load's step in its unit. It stops at the limits a plan is
    /// stored within, a time at 5 s, and a weight at one step, a bar's at the empty bar.
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
            guard let amount = weight.amount.stepped(by: Double(direction) * step, within: range)
            else { return nil }
            weight.amount = amount
            plan.weight = weight
        }
        return plan
    }

    private static let timeStep = 5
}

extension Comparable where Self: AdditiveArithmetic {
    /// The value moved by `delta` and held within `range`, or nil if it's already at the end
    /// `delta` moves toward, so a step never moves the wrong way.
    fileprivate func stepped(by delta: Self, within range: ClosedRange<Self>) -> Self? {
        let canMove = delta > .zero ? self < range.upperBound : self > range.lowerBound
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

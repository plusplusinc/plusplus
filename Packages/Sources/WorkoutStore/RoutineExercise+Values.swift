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
            switch plan.target {
            case let .reps(reps): qualified(reps.formatted(.number.locale(locale)), .target)
            case let .time(seconds):
                qualified(TimeText.text(seconds: seconds, locale: locale), .target)
            }
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
    /// 5 s at a time, a weight its unit's step. It stops at the limits a plan is stored within,
    /// a time at 5 s, and a weight at one step, a bar's at the empty bar.
    public mutating func step(_ part: PlanPart, by direction: Int) {
        switch part {
        case .sets:
            plan.sets = (plan.sets + direction).clamped(to: PlanLimits.sets)
        case .target:
            switch plan.target {
            case let .reps(reps):
                plan.target = .reps((reps + direction).clamped(to: PlanLimits.reps))
            case let .time(seconds):
                let time = (seconds + direction * Self.timeStep)
                    .clamped(to: Self.timeStep ... PlanLimits.seconds.upperBound)
                plan.target = .time(seconds: time)
            }
        case .weight:
            guard var weight = plan.weight else { return }
            let lightest = exercise.load == .bar ? Weight.emptyBar(weight.unit).amount
                : weight.unit.step
            weight.amount = max(weight.amount + Double(direction) * weight.unit.step, lightest)
            plan.weight = weight
        }
    }

    private static let timeStep = 5
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

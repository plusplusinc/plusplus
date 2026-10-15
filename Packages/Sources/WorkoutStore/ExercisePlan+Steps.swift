import Foundation

// The sheet's − and + keys. Each steps to the next value on its grid, so a typed 142.5 lb goes to
// 145 or 140, and stops at the plan's limits.

extension RoutineExercise {
    /// What `part` holds as a number, nil for a weight on an exercise with none: sets, reps,
    /// seconds, or a weight's amount. Its number in the sheet rolls up or down as this rises or
    /// falls.
    public func amount(of part: PlanPart) -> Double? {
        switch part {
        case .sets: Double(plan.sets)
        case .target:
            switch plan.target {
            case let .reps(reps): Double(reps)
            case let .time(seconds): Double(seconds)
            }
        case .weight: exercise.load == nil ? nil : plan.weight?.amount
        }
    }

    /// Whether `part` can step up or down from where it is.
    public func canStep(_ part: PlanPart, up: Bool) -> Bool {
        switch part {
        case .sets:
            return up ? plan.sets < PlanLimits.sets.upperBound :
                plan.sets > PlanLimits.sets.lowerBound
        case .target:
            switch plan.target {
            case let .reps(reps):
                return up ? reps < PlanLimits.reps.upperBound : reps > PlanLimits.reps.lowerBound
            case let .time(seconds):
                return up ? seconds < PlanLimits.seconds.upperBound : seconds > TimeSteps.minimum
            }
        case .weight:
            guard let weight = plan.weight else { return false }
            return up ? weight.amount < PlanLimits.maxWeight : weight.amount > lightest(weight.unit)
        }
    }

    /// Steps `part` up or down, no lower than the lightest weight it can hold.
    public mutating func step(_ part: PlanPart, up: Bool) {
        guard canStep(part, up: up) else { return }
        switch part {
        case .sets:
            plan.sets += up ? 1 : -1
        case .target:
            switch plan.target {
            case let .reps(reps): plan.target = .reps(reps + (up ? 1 : -1))
            case let .time(seconds): plan.target = .time(seconds: TimeSteps.step(seconds, up: up))
            }
        case .weight:
            guard let weight = plan.weight else { return }
            let amount = Self.snapped(weight.amount, step: weight.unit.step, up: up)
            plan.weight = Weight(
                min(max(amount, lightest(weight.unit)), PlanLimits.maxWeight),
                weight.unit,
            )
        }
    }

    /// The lightest weight − reaches: the empty bar for a bar, one step for anything else.
    private func lightest(_ unit: WeightUnit) -> Double {
        exercise.load == .bar ? Weight.emptyBar(unit).amount : unit.step
    }

    /// The next multiple of `step` above `value`, or the one below.
    static func snapped(_ value: Double, step: Double, up: Bool) -> Double {
        var steps = value / step
        // A value on the grid, give or take floating point, is on it.
        if abs(steps - steps.rounded()) < 1e-9 {
            steps = steps.rounded()
        }
        return (up ? steps.rounded(.down) + 1 : steps.rounded(.up) - 1) * step
    }
}

extension WeightUnit {
    /// One step of a weight: 5 lb or 2.5 kg.
    var step: Double {
        switch self {
        case .pounds: 5
        case .kilograms: 2.5
        }
    }
}

extension Weight {
    /// A barbell with nothing on it: 45 lb or 20 kg.
    static func emptyBar(_ unit: WeightUnit) -> Weight {
        switch unit {
        case .pounds: Weight(45, .pounds)
        case .kilograms: Weight(20, .kilograms)
        }
    }
}

/// Time steps by 5 s under a minute and by 15 s from a minute up.
enum TimeSteps {
    static let minimum = 5
    private static let fine = 5
    private static let coarse = 15
    private static let coarseFrom = 60

    static func step(_ seconds: Int, up: Bool) -> Int {
        let next: Int = if up, seconds < coarseFrom {
            min(snapped(seconds, fine, up: true), coarseFrom)
        } else if up {
            snapped(seconds, coarse, up: true)
        } else if seconds > coarseFrom {
            max(snapped(seconds, coarse, up: false), coarseFrom)
        } else {
            snapped(seconds, fine, up: false)
        }
        return min(max(next, minimum), PlanLimits.seconds.upperBound)
    }

    private static func snapped(_ seconds: Int, _ step: Int, up: Bool) -> Int {
        Int(RoutineExercise.snapped(Double(seconds), step: Double(step), up: up))
    }
}

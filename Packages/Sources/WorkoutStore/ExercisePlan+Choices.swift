import Foundation

// The sheet's wheels: what each part offers, and setting a part from what was picked. Every wheel
// holds the row's current value at its place, even off its grid or past its range, so opening a
// wheel never changes a value by itself.

extension RoutineExercise {
    /// What `part` holds as a number, nil for a weight on an exercise with none: sets, reps,
    /// seconds, or a weight's amount.
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

    /// The sets wheel: 1 to 20.
    public var setChoices: [Int] {
        Self.including(plan.sets, in: Array(1 ... 20))
    }

    /// The reps wheel: 1 to 100, or nothing for a timed exercise.
    public var repChoices: [Int] {
        guard case let .reps(reps) = plan.target else { return [] }
        return Self.including(reps, in: Array(1 ... 100))
    }

    /// A time's minutes and seconds, as its two wheels show them.
    public var minutesAndSeconds: (minutes: Int, seconds: Int) {
        guard case let .time(seconds) = plan.target else { return (0, 0) }
        return (seconds / 60, seconds % 60)
    }

    /// The minutes wheel: 0 to 60.
    public var minuteChoices: [Int] {
        Self.including(minutesAndSeconds.minutes, in: Array(0 ... 60))
    }

    /// The seconds wheel: 0 to 55 in 5 s steps.
    public var secondChoices: [Int] {
        Self.including(minutesAndSeconds.seconds, in: Array(stride(from: 0, through: 55, by: 5)))
    }

    /// The shortest time a set holds.
    static let shortestTime = 5

    /// Sets a time from its wheels. A time of nothing is 5 s, the shortest a set holds.
    public mutating func setTime(minutes: Int, seconds: Int) {
        guard case .time = plan.target else { return }
        plan.target = .time(seconds: max(minutes * 60 + seconds, Self.shortestTime))
    }

    /// The weight wheel, in the weight's own unit: the step grid, 5 lb or 2.5 kg, from the
    /// lightest, the empty bar for a bar and one step for anything else, up to 500 lb or 250 kg
    /// on a bar and 150 lb or 70 kg in a hand.
    public var weightChoices: [Double] {
        guard let weight = plan.weight else { return [] }
        let unit = weight.unit
        let heaviest = exercise.load == .bar ? unit.heaviestOnABar : unit.heaviestInAHand
        let grid = Array(stride(from: lightest(unit), through: heaviest, by: unit.step))
        return Self.including(weight.amount, in: grid)
    }

    /// Sets the weight's amount from its wheel, keeping its unit.
    public mutating func setWeight(_ amount: Double) {
        guard let weight = plan.weight else { return }
        plan.weight = Weight(amount, weight.unit)
    }

    /// The lightest weight on the wheel: the empty bar for a bar, one step for anything else.
    private func lightest(_ unit: WeightUnit) -> Double {
        exercise.load == .bar ? Weight.emptyBar(unit).amount : unit.step
    }

    /// `choices` with `value` in its place, if it isn't one of them.
    private static func including<Value: Comparable>(_ value: Value, in choices: [Value])
        -> [Value]
    {
        choices.contains(value) ? choices : (choices + [value]).sorted()
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

    var heaviestOnABar: Double {
        switch self {
        case .pounds: 500
        case .kilograms: 250
        }
    }

    /// A dumbbell or a kettlebell.
    var heaviestInAHand: Double {
        switch self {
        case .pounds: 150
        case .kilograms: 70
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

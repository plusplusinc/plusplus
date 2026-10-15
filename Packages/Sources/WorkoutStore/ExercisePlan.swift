import Foundation

/// What a set is measured in, carrying only its own value.
public enum SetTarget: Equatable, Sendable {
    case reps(Int)
    case time(seconds: Int)
}

/// What a loaded exercise holds. An exercise with no load has no weight at all.
public enum Load: Sendable {
    /// One kettlebell or one dumbbell: the weight is that one.
    case single
    /// A dumbbell in each hand: the weight is each one's.
    case pair
    /// A barbell: the weight is the total, bar included.
    case bar
}

/// The unit a weight was set in. Stored with every weight, so a weight never changes meaning.
public enum WeightUnit: String, Sendable {
    case pounds = "lb"
    case kilograms = "kg"

    /// The unit a new weight takes: pounds in a US region, kilograms elsewhere.
    public init(region locale: Locale) {
        self = locale.measurementSystem == .us ? .pounds : .kilograms
    }
}

public struct Weight: Equatable, Sendable {
    public var amount: Double
    public var unit: WeightUnit

    public init(_ amount: Double, _ unit: WeightUnit) {
        self.amount = amount
        self.unit = unit
    }
}

/// An exercise's values in a routine: every set the same, so one sets count, one target, and one
/// weight.
public struct ExercisePlan: Equatable, Sendable {
    public var sets: Int
    public var target: SetTarget
    /// Nil when not set, and always for an exercise with no load.
    public var weight: Weight?

    public init(sets: Int, target: SetTarget, weight: Weight? = nil) {
        self.sets = sets
        self.target = target
        self.weight = weight
    }
}

/// A value a plan holds, and a row in the exercise's sheet.
public enum PlanPart: Sendable {
    case sets
    /// Reps or time.
    case target
    case weight
}

extension Exercise {
    /// The parts of a plan this exercise has, in the sheet's order: weight only with a load.
    public var planParts: [PlanPart] {
        load == nil ? [.sets, .target] : [.sets, .target, .weight]
    }
}

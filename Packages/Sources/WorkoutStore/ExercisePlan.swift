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

    /// One step of its weight: 5 lb; in kilograms, 2.5 for a bar's plates and 2 for a
    /// dumbbell or kettlebell, the steps their starting weights come in.
    func step(in unit: WeightUnit) -> Double {
        switch (unit, self) {
        case (.pounds, _): 5
        case (.kilograms, .bar): 2.5
        case (.kilograms, .single), (.kilograms, .pair): 2
        }
    }
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

    /// A barbell with nothing on it: 45 lb or 20 kg.
    static func emptyBar(_ unit: WeightUnit) -> Self {
        switch unit {
        case .pounds: Self(45, .pounds)
        case .kilograms: Self(20, .kilograms)
        }
    }
}

/// Where a loaded exercise's weight starts, in each unit: its own value from the kit that unit
/// comes in (dumbbells in 2 kg steps, kettlebells at 8, 12, 16 kg), not a conversion.
struct StartingWeight: Equatable, Sendable {
    let pounds: Double
    let kilograms: Double

    func weight(in unit: WeightUnit) -> Weight {
        switch unit {
        case .pounds: Weight(pounds, .pounds)
        case .kilograms: Weight(kilograms, .kilograms)
        }
    }
}

/// An exercise's values in a routine: every set the same, so one sets count, one target, and one
/// weight, and the gaps around them, in seconds.
public struct ExercisePlan: Equatable, Sendable {
    public var sets: Int
    public var target: SetTarget
    /// Nil only for an exercise with no load; one that holds a weight always has one.
    public var weight: Weight?
    /// Between one set and the next; 0 for none.
    public var rest: Int
    /// Between a per-side set's left and its right; nil for an exercise not done per side.
    public var switchSides: Int?
    /// After the last set, before the next exercise.
    public var transition: Int

    public init(
        sets: Int,
        target: SetTarget,
        weight: Weight? = nil,
        rest: Int = 0,
        switchSides: Int? = nil,
        transition: Int = 0,
    ) {
        self.sets = sets
        self.target = target
        self.weight = weight
        self.rest = rest
        self.switchSides = switchSides
        self.transition = transition
    }
}

/// A superset's own gaps, the same on every member, each nil until set: a nil reads as derived
/// from the members (the rest after a round) or as the default (the switch and the transition).
/// Empty on a plain row.
public struct RoundRest: Equatable, Sendable {
    /// Between one member's set and the next member's, within a round.
    public var switchPartners: Int?
    /// After a round's last member, before the next round.
    public var afterRound: Int?
    /// After the last round, before the next exercise.
    public var transition: Int?

    public init(switchPartners: Int? = nil, afterRound: Int? = nil, transition: Int? = nil) {
        self.switchPartners = switchPartners
        self.afterRound = afterRound
        self.transition = transition
    }
}

/// A value a plan holds.
public enum PlanPart: Sendable {
    case sets
    /// Reps or time.
    case target
    case weight
}

extension Exercise {
    /// The parts of a plan this exercise has, in the order its row reads them: weight only with a
    /// load.
    public var planParts: [PlanPart] {
        load == nil ? [.sets, .target] : [.sets, .target, .weight]
    }
}

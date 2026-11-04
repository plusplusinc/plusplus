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
/// weight, and the rest after each, in seconds.
public struct ExercisePlan: Equatable, Sendable {
    public var sets: Int
    public var target: SetTarget
    /// Nil only for an exercise with no load; one that holds a weight always has one.
    public var weight: Weight?
    /// After each set, the last included, which is the way to the next exercise, in seconds; 0
    /// for none. The last rest the user set, nil if never, kept while `isRestAuto`, so turning
    /// that off brings it back (`RoutineExercise.rest`).
    public var rest: Int?
    /// Whether the rest follows the reps or time as they change, as it does until the user sets
    /// one.
    public var isRestAuto: Bool

    public init(
        sets: Int,
        target: SetTarget,
        weight: Weight? = nil,
        rest: Int? = nil,
        isRestAuto: Bool = true,
    ) {
        self.sets = sets
        self.target = target
        self.weight = weight
        self.rest = rest
        self.isRestAuto = isRestAuto
    }
}

/// A superset's own rest, the same on every member: while automatic, derived from the members;
/// the last value set by hand kept for when it isn't. Empty on a plain row.
public struct RoundRest: Equatable, Sendable {
    /// After each round, the last included: the last set by hand, nil if never.
    public var afterRound: Int?
    /// Whether the rest is derived from the members, as it is until the user sets one.
    public var isAuto: Bool

    public init(afterRound: Int? = nil, isAuto: Bool = true) {
        self.afterRound = afterRound
        self.isAuto = isAuto
    }
}

/// A value a plan holds.
public enum PlanPart: Sendable {
    case sets
    /// Reps or time.
    case target
    case weight
    /// After each set.
    case rest
}

extension Exercise {
    /// The parts of a plan this exercise has, in the order its row reads them: weight only with a
    /// load.
    public var planParts: [PlanPart] {
        load == nil ? [.sets, .target] : [.sets, .target, .weight]
    }
}

/// A value a routine row's sheet steps: one of its plan, or, in a superset, the rest after each
/// round, shared with its partners.
public enum SheetPart: Hashable, Sendable {
    case plan(PlanPart)
    case restAfterRound
}

extension Collection<RoutineExercise> {
    /// What a rest set by hand on these rows stays put through: "reps", "the time" where every
    /// set is timed, or "reps or time" where some are.
    public var restChange: String {
        let timed = filter {
            if case .time = $0.plan.target {
                true
            } else {
                false
            }
        }.count
        return timed == 0 ? "reps" : timed == count ? "the time" : "reps or time"
    }
}

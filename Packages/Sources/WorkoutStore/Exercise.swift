import Foundation

/// What an exercise is: its name, the muscle groups it works, and the equipment it uses.
/// A routine holds instances of it, as `RoutineExercise`.
public struct Exercise: Identifiable, Equatable, Sendable {
    /// A stable slug, so a routine can refer to a built-in exercise by something its display
    /// name can change without breaking.
    public let id: String
    public let name: String
    /// One for a built-in, the group it mostly works; any number, all equal, for one someone
    /// created. Never empty.
    public let muscleGroups: Set<MuscleGroup>
    /// Empty for bodyweight.
    public let equipment: Set<Equipment>
    /// The sets and target a new row starts with. Its target's case is how a set is measured,
    /// reps or time, so the measure and its default can't disagree. Its weight is `startsAt`'s.
    private let plan: ExercisePlan
    /// What a set holds, or nil for no weight at all.
    public let load: Load?
    /// The weight a new row starts at, for a load other than a bar, which starts at the empty
    /// bar.
    let startsAt: StartingWeight?
    /// Whether each side is its own set. A move that alternates within a set is not per side.
    public let isPerSide: Bool
    /// What it does, finer than its group, for naming a routine.
    let tags: ExerciseTags
    /// How it rests: from its tags for a built-in, from its group for one known only by that.
    let restKind: RestKind

    init(
        id: String,
        name: String,
        muscleGroups: Set<MuscleGroup>,
        equipment: Set<Equipment> = [],
        plan defaultPlan: ExercisePlan,
        load: Load? = nil,
        startsAt: StartingWeight? = nil,
        perSide isPerSide: Bool = false,
        tags: ExerciseTags,
        rests restKind: RestKind? = nil,
    ) {
        self.id = id
        self.name = name
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        plan = defaultPlan
        self.load = load
        self.startsAt = startsAt
        self.isPerSide = isPerSide
        self.tags = tags
        self.restKind = restKind ?? RestKind(tags: tags)
    }

    /// The values a new row starts with, a weight in `unit` included for an exercise that holds
    /// one: the empty bar for a bar, else a light, safe start in the steps real kit comes in.
    /// Its rest is unset, so it follows the reps.
    public func defaultPlan(in unit: WeightUnit) -> ExercisePlan {
        var plan = plan
        plan.weight = startingWeight(in: unit)
        return plan
    }

    /// Nil only for an exercise with no load. A loaded one missing its start, which a test rules
    /// out for the built-ins, starts at one step.
    func startingWeight(in unit: WeightUnit) -> Weight? {
        switch load {
        case nil: nil
        case .bar: .emptyBar(unit)
        case let .some(load): startsAt?.weight(in: unit) ?? Weight(load.step(in: unit), unit)
        }
    }

    /// The equipment as a line of text in display order, "Dumbbells, bench", or nil for
    /// bodyweight, which shows no line at all.
    public var equipmentLine: String? {
        equipment.line
    }
}

extension [Exercise] {
    /// Every piece of equipment these exercises use, once each, in display order.
    public var equipment: [Equipment] {
        Equipment.allCases.filter { piece in contains { $0.equipment.contains(piece) } }
    }

    /// The exercises whose names contain the query, in order, ignoring case, diacritics, and
    /// everything but letters and digits: "pullup", "pull up", and "PULL-UP" all find Pull-up,
    /// and an apostrophe of either kind, or none, finds Farmer’s carry. A query with nothing
    /// left to match matches everything.
    public func matching(_ query: String) -> [Exercise] {
        let query = Self.lettersAndDigits(query)
        guard !query.isEmpty else { return self }
        return filter { Self.lettersAndDigits($0.name).localizedStandardContains(query) }
    }

    /// Whether one of these is named `name`, by the search's own folding: "pull up" is
    /// Pull-up's name. A name with no letters or digits names none.
    public func hasExercise(named name: String) -> Bool {
        let name = Self.lettersAndDigits(name)
        guard !name.isEmpty else { return false }
        return contains {
            Self.lettersAndDigits($0.name)
                .compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private static func lettersAndDigits(_ text: String) -> String {
        let kept = text.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
        return String(String.UnicodeScalarView(kept))
    }
}

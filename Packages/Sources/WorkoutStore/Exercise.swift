import Foundation

/// What an exercise is: its name, the muscle group it mostly works, and the equipment it uses.
/// A routine holds instances of it, as `RoutineExercise`.
public struct Exercise: Identifiable, Equatable, Sendable {
    /// A stable slug, so a routine can refer to a built-in exercise by something its display
    /// name can change without breaking.
    public let id: String
    public let name: String
    public let muscleGroup: MuscleGroup
    /// Empty for bodyweight.
    public let equipment: Set<Equipment>
    /// The values a new row starts with. Its target's case is how a set is measured, reps or
    /// time, so the measure and its default can't disagree. Its weight is never set.
    public let defaultPlan: ExercisePlan
    /// What a set holds, or nil for no weight at all.
    public let load: Load?
    /// Whether each side is its own set. A move that alternates within a set is not per side.
    public let isPerSide: Bool
    /// What it does, finer than its group, for naming a routine.
    let tags: ExerciseTags

    init(
        id: String,
        name: String,
        muscleGroup: MuscleGroup,
        equipment: Set<Equipment> = [],
        plan defaultPlan: ExercisePlan,
        load: Load? = nil,
        perSide isPerSide: Bool = false,
        tags: ExerciseTags,
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.defaultPlan = defaultPlan
        self.load = load
        self.isPerSide = isPerSide
        self.tags = tags
    }

    /// The equipment as a line of text in display order, "Dumbbells, bench", or nil for
    /// bodyweight, which shows no line at all.
    public var equipmentLine: String? {
        let names = Equipment.allCases.filter(equipment.contains).map(\.name)
        guard let first = names.first else { return nil }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }
}

extension [Exercise] {
    /// The exercises whose names contain the query, in order, ignoring case, diacritics, and
    /// everything but letters and digits: "pullup", "pull up", and "PULL-UP" all find Pull-up,
    /// and an apostrophe of either kind, or none, finds Farmer’s carry. A query with nothing
    /// left to match matches everything.
    public func matching(_ query: String) -> [Exercise] {
        let query = Self.lettersAndDigits(query)
        guard !query.isEmpty else { return self }
        return filter { Self.lettersAndDigits($0.name).localizedStandardContains(query) }
    }

    private static func lettersAndDigits(_ text: String) -> String {
        let kept = text.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
        return String(String.UnicodeScalarView(kept))
    }
}

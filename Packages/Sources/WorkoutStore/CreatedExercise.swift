import Foundation

/// How a set is measured, without its number: what a created exercise is set to.
public enum Measure: String, CaseIterable, Sendable {
    case reps
    case time

    public var name: String {
        switch self {
        case .reps: "Reps"
        case .time: "Time"
        }
    }
}

/// An exercise someone made, as they set it: only the five settings the form asks for. Its load,
/// starting weight, plan, rest, and naming are derived (`Exercise(created:)`), so a later change
/// to a derivation reaches exercises already made.
public struct CreatedExercise: Identifiable, Equatable, Sendable {
    /// "created:" and a UUID, made once, never from the name, so it can't collide with a
    /// built-in slug (letters, digits, and hyphens) or another device's exercise.
    public let id: String
    public var name: String
    /// Every group checked, all equal; none at all is allowed, and rests as single-joint.
    public var muscleGroups: Set<MuscleGroup>
    public var equipment: Set<Equipment>
    public var measure: Measure
    public var isPerSide: Bool
    public var createdAt: Date

    public init(
        id: String = Self.newID(),
        name: String,
        muscleGroups: Set<MuscleGroup>,
        equipment: Set<Equipment> = [],
        measure: Measure = .reps,
        isPerSide: Bool = false,
        createdAt: Date = .now,
    ) {
        self.id = id
        self.name = name
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.measure = measure
        self.isPerSide = isPerSide
        self.createdAt = createdAt
    }

    static let idPrefix = "created:"

    public static func newID() -> String {
        idPrefix + UUID().uuidString.lowercased()
    }

    /// Whether these settings make an exercise to add, or, `besides` an exercise's id, to save
    /// over it: a name that is no other exercise's (by the search's folding). No muscle group is
    /// needed: some exercises, such as corpse pose, work none.
    public static func canAdd(
        named name: String,
        to exercises: ExerciseList,
        besides id: String? = nil,
    ) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !exercises.hasExercise(named: name, besides: id)
    }
}

extension Exercise {
    /// The definition a created exercise works as, the same the built-ins have. It holds a
    /// weight by the first of barbell (a bar), dumbbells (one when per side, else a pair),
    /// kettlebell, and medicine ball (one) it uses, starting where the lightest built-in of that
    /// piece starts; 3 × 10 reps or 3 × 30 s; rests as the longest-resting of its groups; and is
    /// named by its groups alone, every one of them.
    public init(created: CreatedExercise) {
        let (load, startsAt) = Self.derivedLoad(
            equipment: created.equipment,
            isPerSide: created.isPerSide,
        )
        self.init(
            id: created.id,
            name: created.name,
            muscleGroups: created.muscleGroups,
            equipment: created.equipment,
            plan: Self.derivedPlan(created.measure),
            load: load,
            startsAt: startsAt,
            perSide: created.isPerSide,
            tags: .groupOnly,
            rests: RestKind(groups: created.muscleGroups),
        )
    }

    /// What an exercise of this equipment holds and starts at, when nothing shipped says: by the
    /// first of barbell (a bar), dumbbells (one when per side, else a pair), kettlebell, and
    /// medicine ball (one), from the lightest built-in of that piece; else no weight.
    static func derivedLoad(
        equipment: Set<Equipment>,
        isPerSide: Bool,
    ) -> (load: Load?, startsAt: StartingWeight?) {
        if equipment.contains(.barbell) {
            (.bar, nil)
        } else if equipment.contains(.dumbbells) {
            (isPerSide ? .single : .pair, Equipment.dumbbells.lightStart)
        } else if equipment.contains(.kettlebell) {
            (.single, Equipment.kettlebell.lightStart)
        } else if equipment.contains(.medicineBall) {
            (.single, Equipment.medicineBall.lightStart)
        } else {
            (nil, nil)
        }
    }

    /// The plan a new row starts with for `measure`, when nothing shipped says: 3 × 10 reps or
    /// 3 × 30 s.
    static func derivedPlan(_ measure: Measure) -> ExercisePlan {
        let target: SetTarget = switch measure {
        case .reps: .reps(10)
        case .time: .time(seconds: 30)
        }
        return ExercisePlan(sets: 3, target: target)
    }
}

extension Equipment {
    /// The lightest start a built-in held in this piece has, for a created exercise to start
    /// at; nil for a bar, which starts empty, and for kit that holds no weight.
    var lightStart: StartingWeight? {
        switch self {
        case .dumbbells, .medicineBall: StartingWeight(pounds: 10, kilograms: 4)
        case .kettlebell: StartingWeight(pounds: 20, kilograms: 8)
        case .barbell, .bench, .band, .pullUpBar, .rings, .balanceBoard: nil
        }
    }
}

extension ExerciseTags {
    /// For an exercise known only by its muscle groups: no movement and no muscles, so a routine
    /// is named for its groups, never a push or pull day on a claim nobody made.
    static let groupOnly = ExerciseTags(nil, [])
}

/// What kind of exercise one is, as Add exercise's Kind filter offers it. The one balance
/// exercise reads Strength; a created exercise, which has no kind to set yet, reads Strength too.
public enum ExerciseKind: CaseIterable, Sendable {
    case strength
    case stretch
    case conditioning

    public var name: String {
        switch self {
        case .strength: "Strength"
        case .stretch: "Stretch"
        case .conditioning: "Conditioning"
        }
    }
}

extension Exercise {
    public var kind: ExerciseKind {
        switch tags.kind {
        case .strength, .balance: .strength
        case .stretch: .stretch
        case .conditioning: .conditioning
        }
    }
}

/// One of the Equipment filter's choices: no equipment at all, or a piece. Declared in the
/// filter's display order, No equipment first.
public enum EquipmentChoice: Hashable, Sendable {
    case none
    case piece(Equipment)

    public static let allCases: [Self] = [.none] + Equipment.allCases.map(Self.piece)

    public var name: String {
        switch self {
        case .none: "No equipment"
        case let .piece(piece): piece.name
        }
    }
}

extension ExerciseTags.Muscle {
    /// The group the muscle belongs to. Lower back is Back; hip flexors are Legs.
    var group: MuscleGroup {
        switch self {
        case .chest: .chest
        case .lats, .upperBack, .lowerBack: .back
        case .frontDelts, .sideDelts, .rearDelts: .shoulders
        case .biceps, .triceps, .forearms: .arms
        case .hipFlexors, .glutes, .quads, .hamstrings, .calves: .legs
        case .abs, .obliques: .core
        }
    }
}

/// What Add exercise's list is narrowed by: muscle groups, a kind, and equipment, each off
/// while empty. Every filter that is on must hold, and the search with them.
///
/// - Muscle, any of: an exercise shows when it works a chosen group mainly (its own groups, or
///   a primary muscle's) or along the way (a secondary muscle's). Those that mainly do come
///   first, A to Z within each.
/// - Kind, one at a time.
/// - Equipment: everything an exercise uses is among the chosen pieces; a bodyweight exercise
///   shows only with No equipment chosen.
public struct ExerciseFilter: Equatable, Sendable {
    public var muscleGroups: Set<MuscleGroup>
    public var kind: ExerciseKind?
    public var equipment: Set<EquipmentChoice>

    public init(
        muscleGroups: Set<MuscleGroup> = [],
        kind: ExerciseKind? = nil,
        equipment: Set<EquipmentChoice> = [],
    ) {
        self.muscleGroups = muscleGroups
        self.kind = kind
        self.equipment = equipment
    }

    /// Whether any filter is on.
    public var isOn: Bool {
        !muscleGroups.isEmpty || kind != nil || !equipment.isEmpty
    }

    /// Chooses `kind`, or clears it when it is the one chosen.
    public mutating func toggle(_ kind: ExerciseKind) {
        self.kind = self.kind == kind ? nil : kind
    }

    /// The Muscle button's words while a group is chosen, in body order: "Chest, Back" for two,
    /// "3 muscles" past two; nil while off.
    public var muscleLabel: String? {
        Self.label(MuscleGroup.allCases.filter(muscleGroups.contains).map(\.name)) {
            "\($0.count) muscles"
        }
    }

    /// The Kind button's words while a kind is chosen.
    public var kindLabel: String? {
        kind?.name
    }

    /// The Equipment button's words while a choice is on, in display order: "Dumbbells, Bench"
    /// for two, "Dumbbells +2" past two; nil while off.
    public var equipmentLabel: String? {
        Self.label(EquipmentChoice.allCases.filter(equipment.contains).map(\.name)) {
            "\($0[0]) +\($0.count - 1)"
        }
    }

    private static func label(_ names: [String], past two: ([String]) -> String) -> String? {
        switch names.count {
        case 0: nil
        case 1, 2: names.joined(separator: ", ")
        default: two(names)
        }
    }

    /// Whether `exercise` passes the muscle filter, and whether it mainly works a chosen group:
    /// nil when it doesn't pass.
    fileprivate func muscleMatch(_ exercise: Exercise) -> MuscleMatch? {
        guard !muscleGroups.isEmpty else { return .mainly }
        let primary = exercise.muscleGroups.union(exercise.tags.primary.map(\.group))
        if !primary.isDisjoint(with: muscleGroups) {
            return .mainly
        }
        if !Set(exercise.tags.secondary.map(\.group)).isDisjoint(with: muscleGroups) {
            return .alongTheWay
        }
        return nil
    }

    fileprivate func passesKind(_ exercise: Exercise) -> Bool {
        kind.map { exercise.kind == $0 } ?? true
    }

    fileprivate func passesEquipment(_ exercise: Exercise) -> Bool {
        guard !equipment.isEmpty else { return true }
        guard !exercise.equipment.isEmpty else { return equipment.contains(.none) }
        return exercise.equipment.allSatisfy { equipment.contains(.piece($0)) }
    }

    fileprivate enum MuscleMatch {
        case mainly
        case alongTheWay
    }
}

/// What a filtered list shows.
public struct FilteredExercises: Equatable, Sendable {
    /// The exercises every filter and the search hold for: those that mainly work a chosen
    /// group first, then those that work one along the way, A to Z within each.
    public let matches: [Exercise]
}

extension ExerciseList {
    /// The exercises matching `query` that pass `filter`, in its order (`ExerciseFilter`).
    public func filtered(by filter: ExerciseFilter, matching query: String) -> FilteredExercises {
        var mainly: [Exercise] = []
        var alongTheWay: [Exercise] = []
        for exercise in matching(query)
            where filter.passesKind(exercise) && filter.passesEquipment(exercise)
        {
            switch filter.muscleMatch(exercise) {
            case .mainly: mainly.append(exercise)
            case .alongTheWay: alongTheWay.append(exercise)
            case nil: break
            }
        }
        return FilteredExercises(matches: mainly + alongTheWay)
    }
}

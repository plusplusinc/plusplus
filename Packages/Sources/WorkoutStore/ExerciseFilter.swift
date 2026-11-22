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
public struct ExerciseFilter: Hashable, Sendable {
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

extension ExerciseFilter {
    /// The muscle groups Create gives the exercise it makes: the chosen ones.
    public var carriedGroups: Set<MuscleGroup> {
        muscleGroups
    }

    /// The equipment Create gives the exercise it makes: the chosen pieces. No equipment adds
    /// none, which an exercise reads as bodyweight.
    public var carriedEquipment: Set<Equipment> {
        Set(equipment.compactMap {
            if case let .piece(piece) = $0 {
                piece
            } else {
                nil
            }
        })
    }

    /// What Create carries, as its row's detail line reads it: the chosen groups in body order,
    /// then the chosen equipment in display order, No equipment as "Bodyweight"
    /// ("Chest, Dumbbells"). Kind is never carried, so nil when only Kind is on.
    public var carriedLine: String? {
        let groups = MuscleGroup.allCases.filter(muscleGroups.contains).map(\.name)
        let kit = EquipmentChoice.allCases.filter(equipment.contains).map { choice in
            choice == .none ? "Bodyweight" : choice.name
        }
        let names = groups + kit
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}

/// What a filtered list shows.
public struct FilteredExercises: Equatable, Sendable {
    /// The exercises every filter and the search hold for: those that mainly work a chosen
    /// group first, then those that work one along the way, A to Z within each.
    public let matches: [Exercise]
    /// The exercises one piece short of the chosen equipment, a section per missing piece.
    public let alsoNeeds: [Section]

    /// Exercises that pass every filter but equipment, use a chosen piece, and miss exactly
    /// `piece`.
    public struct Section: Identifiable, Equatable, Sendable {
        public let piece: Equipment
        public let exercises: [Exercise]

        public var id: Equipment {
            piece
        }
    }
}

extension ExerciseList {
    /// The exercises matching `query` that pass `filter`, in its order (`ExerciseFilter`), and
    /// those one piece of equipment short: among the exercises that pass search, muscle, and
    /// kind, each that uses a chosen piece and misses exactly one goes in that piece's section.
    /// Sections run by how many exercises each holds, most first, a tie in display order; inside
    /// one, the matches' order. An exercise is in the matches or in one section, never both.
    public func filtered(by filter: ExerciseFilter, matching query: String) -> FilteredExercises {
        var mainly: [Exercise] = []
        var alongTheWay: [Exercise] = []
        for exercise in matching(query) where filter.passesKind(exercise) {
            switch filter.muscleMatch(exercise) {
            case .mainly: mainly.append(exercise)
            case .alongTheWay: alongTheWay.append(exercise)
            case nil: break
            }
        }
        let ordered = mainly + alongTheWay
        let chosen = filter.carriedEquipment
        var short: [Equipment: [Exercise]] = [:]
        for exercise in ordered where !filter.passesEquipment(exercise) {
            let missing = exercise.equipment.subtracting(chosen)
            if missing.count == 1, let piece = missing.first,
               !exercise.equipment.isDisjoint(with: chosen)
            {
                short[piece, default: []].append(exercise)
            }
        }
        let sections = Equipment.allCases.compactMap { piece in
            short[piece].map { FilteredExercises.Section(piece: piece, exercises: $0) }
        }
        // A stable sort, so a tie keeps display order.
        let byCount = sections.enumerated().sorted {
            ($0.element.exercises.count, -$0.offset) > ($1.element.exercises.count, -$1.offset)
        }.map(\.element)
        return FilteredExercises(
            matches: ordered.filter(filter.passesEquipment),
            alsoNeeds: byCount,
        )
    }

    /// The name Create gives an exercise when nothing is typed, as Customize opens on it.
    public static let unnamedExerciseName = "New exercise"

    /// `base`, or the first of "`base` 2", "`base` 3", … that no exercise is named.
    public func unusedName(_ base: String) -> String {
        guard hasExercise(named: base) else { return base }
        var number = 2
        while hasExercise(named: "\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }
}

extension Equipment {
    /// The piece as "Also needs …" reads it: "a bench", "dumbbells".
    public var needed: String {
        switch self {
        case .dumbbells: "dumbbells"
        case .kettlebell: "a kettlebell"
        case .barbell: "a barbell"
        case .medicineBall: "a medicine ball"
        case .bench: "a bench"
        case .band: "a band"
        case .pullUpBar: "a pull-up bar"
        case .rings: "rings"
        case .balanceBoard: "a balance board"
        }
    }
}

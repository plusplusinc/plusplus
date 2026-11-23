/// What the Workouts list is narrowed by: muscle groups, equipment, and length, each off while
/// empty or full. Every filter that is on must hold. It reads only a workout's summary.
///
/// - Muscle, any of: a workout shows when it mainly works a chosen group.
/// - Equipment: everything the workout uses is among the chosen pieces, so a bodyweight
///   exercise never counts, a workout using nothing passes any choice, and No equipment alone
///   passes only workouts using nothing.
/// - Length: the minutes its row reads (`WorkoutSummary.minutes`) are in the range.
public struct WorkoutFilter: Hashable, Sendable {
    public var muscleGroups: Set<MuscleGroup>
    public var equipment: Set<EquipmentChoice>
    public var length: LengthRange

    public init(
        muscleGroups: Set<MuscleGroup> = [],
        equipment: Set<EquipmentChoice> = [],
        length: LengthRange = .full,
    ) {
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.length = length
    }

    public var isOn: Bool {
        !muscleGroups.isEmpty || !equipment.isEmpty || length != .full
    }

    /// The Muscle button's words, as Add exercise's: "Chest, Back", "3 muscles"; nil while off.
    public var muscleLabel: String? {
        ExerciseFilter(muscleGroups: muscleGroups).muscleLabel
    }

    /// The Equipment button's words, as Add exercise's: "Dumbbells +2"; nil while off.
    public var equipmentLabel: String? {
        ExerciseFilter(equipment: equipment).equipmentLabel
    }

    /// The Length button's words: "25–45 min", "≥ 45 min" with no upper limit, "≤ 20 min" from
    /// 0, "20 min" for one length; nil while off. Both ends count, since a length is a rounded
    /// figure, so a preset reads as any range does.
    public var lengthLabel: String? {
        guard length != .full else { return nil }
        guard let upper = length.upper else { return "≥ \(length.lower) min" }
        guard length.lower != 0 else { return "≤ \(upper) min" }
        guard length.lower != upper else { return "\(upper) min" }
        return "\(length.lower)–\(upper) min"
    }

    /// Whether a workout with `summary` shows; one with none shows only while the filter is off.
    public func passes(_ summary: WorkoutSummary?) -> Bool {
        guard isOn else { return true }
        guard let summary else { return false }
        if !muscleGroups.isEmpty,
           !summary.muscles.contains(where: { muscleGroups.contains($0.group) })
        {
            return false
        }
        if !equipment.isEmpty, !summary.equipment.allSatisfy({ equipment.contains(.piece($0)) }) {
            return false
        }
        return length.contains(summary.minutes)
    }

    /// The count line's words: "2 workouts", "1 workout", "0 workouts".
    public static func countText(_ count: Int) -> String {
        count == 1 ? "1 workout" : "\(count) workouts"
    }
}

/// A span of minutes on the Length wheels' 5-minute grid: a lower end from 0 to `top`, and an
/// upper end from 0 to `top` or none (nil, the wheel's "∞"), meaning no upper limit. The ends
/// never cross: moving one past the other carries the other with it. 0 to no limit is the
/// filter off.
public struct LengthRange: Hashable, Sendable {
    public private(set) var lower: Int
    /// The upper end, nil for no upper limit.
    public private(set) var upper: Int?

    /// The wheels' highest number.
    public static let top = 90
    /// The wheels' step.
    public static let step = 5
    public static let full = Self(lower: 0, upper: nil)

    /// The left wheel's values, 0 to `top`.
    public static let lowerValues = Array(stride(from: 0, through: top, by: step))
    /// The right wheel's values: 0 to `top`, then no upper limit.
    public static let upperValues: [Int?] = lowerValues.map(Optional.some) + [nil]

    public init(lower: Int, upper: Int?) {
        self.lower = upper.map { min(lower, $0) } ?? lower
        self.upper = upper
    }

    /// Sets the lower end, carrying the upper up to it when it passes.
    public mutating func setLower(_ minutes: Int) {
        lower = minutes
        if let upper, upper < minutes {
            self.upper = minutes
        }
    }

    /// Sets the upper end, nil for no limit, carrying the lower down to it when it passes.
    public mutating func setUpper(_ minutes: Int?) {
        upper = minutes
        if let minutes {
            lower = min(lower, minutes)
        }
    }

    public func contains(_ minutes: Int) -> Bool {
        minutes >= lower && upper.map { minutes <= $0 } ?? true
    }

    /// The preset this range is, if any.
    public var preset: Preset? {
        Preset.allCases.first { $0.range == self }
    }

    public enum Preset: CaseIterable, Sendable {
        case upTo20
        case twentyToForty
        case from40

        public var name: String {
            switch self {
            case .upTo20: "≤ 20 min"
            case .twentyToForty: "20–40 min"
            case .from40: "≥ 40 min"
            }
        }

        /// Neighbors share an end: a workout that reads 20 minutes is in the first two.
        public var range: LengthRange {
            switch self {
            case .upTo20: LengthRange(lower: 0, upper: 20)
            case .twentyToForty: LengthRange(lower: 20, upper: 40)
            case .from40: LengthRange(lower: 40, upper: nil)
            }
        }
    }
}

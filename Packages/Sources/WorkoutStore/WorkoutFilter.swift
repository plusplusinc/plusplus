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

    /// The Length button's words: the preset's own while the range is one, else "25–45 min";
    /// nil while off.
    public var lengthLabel: String? {
        guard length != .full else { return nil }
        if let preset = length.preset {
            return preset.name
        }
        if length.upper >= LengthRange.top {
            return "Over \(length.lower) min"
        }
        guard length.lower != length.upper else { return "\(length.lower) min" }
        return "\(length.lower)–\(length.upper) min"
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

/// A span of minutes on the Length wheels' 5-minute grid, from 0 to `top`, which means no upper
/// limit. The full span is the filter off.
public struct LengthRange: Hashable, Sendable {
    public private(set) var lower: Int
    public private(set) var upper: Int

    /// The wheels' last value, read as "and longer".
    public static let top = 180
    public static let full = Self(lower: 0, upper: top)

    public init(lower: Int, upper: Int) {
        self.lower = min(lower, upper)
        self.upper = upper
    }

    /// Sets the lower end, carrying the upper up to it when it passes.
    public mutating func setLower(_ minutes: Int) {
        lower = minutes
        upper = max(upper, minutes)
    }

    /// Sets the upper end, carrying the lower down to it when it passes.
    public mutating func setUpper(_ minutes: Int) {
        upper = minutes
        lower = min(lower, minutes)
    }

    public func contains(_ minutes: Int) -> Bool {
        minutes >= lower && (upper >= Self.top || minutes <= upper)
    }

    /// The preset this range is, if any.
    public var preset: Preset? {
        Preset.allCases.first { $0.range == self }
    }

    public enum Preset: CaseIterable, Sendable {
        case under20
        case twentyToForty
        case over40

        public var name: String {
            switch self {
            case .under20: "Under 20 min"
            case .twentyToForty: "20–40 min"
            case .over40: "Over 40 min"
            }
        }

        public var range: LengthRange {
            switch self {
            case .under20: LengthRange(lower: 0, upper: 15)
            case .twentyToForty: LengthRange(lower: 20, upper: 40)
            case .over40: LengthRange(lower: 45, upper: LengthRange.top)
            }
        }
    }
}

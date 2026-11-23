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

    /// The Length button's words (`LengthRange.label`); nil while off.
    public var lengthLabel: String? {
        guard length != .full else { return nil }
        return length.label
    }

    /// The Length button's words as VoiceOver reads them, without the symbols: "20 minutes or
    /// less", "40 minutes or more", "25 to 45 minutes"; nil while off.
    public var lengthSpoken: String? {
        guard length != .full else { return nil }
        return length.spoken
    }

    /// Whether a workout with `summary` shows; one with none shows only while the filter is off.
    public func passes(_ summary: WorkoutSummary?) -> Bool {
        guard isOn else { return true }
        guard let summary else { return false }
        return passesAllButEquipment(summary) && passesEquipment(summary)
    }

    private func passesAllButEquipment(_ summary: WorkoutSummary) -> Bool {
        if !muscleGroups.isEmpty,
           !summary.muscles.contains(where: { muscleGroups.contains($0.group) })
        {
            return false
        }
        return length.contains(summary.minutes)
    }

    private func passesEquipment(_ summary: WorkoutSummary) -> Bool {
        equipment.isEmpty || summary.equipment.allSatisfy { equipment.contains(.piece($0)) }
    }

    /// The workouts that pass, in `workouts`' order, and those one piece of equipment short
    /// among those that pass Muscle and Length (`NeedsSection`), inside a section in
    /// `workouts`' order. A workout is in the matches or in one section, never both. `summary`
    /// gives each workout's summary, so a list that has them already need not work them out
    /// again.
    public func filtered(
        _ workouts: [Workout],
        summary: (Workout) -> WorkoutSummary?,
    ) -> FilteredWorkouts {
        var matches: [Workout] = []
        var short: [(Workout, Set<Equipment>)] = []
        for workout in workouts {
            let summary = summary(workout)
            if passes(summary) {
                matches.append(workout)
            } else if let summary, passesAllButEquipment(summary) {
                short.append((workout, Set(summary.equipment)))
            }
        }
        let chosen = ExerciseFilter(equipment: equipment).carriedEquipment
        let sections = NeedsSection.sections(of: short, chosen: chosen, uses: \.1)
        return FilteredWorkouts(
            matches: matches,
            alsoNeeds: sections.map { NeedsSection(piece: $0.piece, items: $0.items.map(\.0)) },
        )
    }

    /// The count line's words: "2 workouts", "1 workout", "0 workouts".
    public static func countText(_ count: Int) -> String {
        count == 1 ? "1 workout" : "\(count) workouts"
    }
}

/// What the filtered Workouts list shows, as Add exercise's (`FilteredExercises`).
public struct FilteredWorkouts: Equatable, Sendable {
    /// The workouts every filter holds for, in the list's order.
    public let matches: [Workout]
    /// The workouts one piece short of the chosen equipment, a section per missing piece.
    public let alsoNeeds: [NeedsSection<Workout>]
}

/// A span of minutes on the Length wheels' 5-minute grid: a lower end from 0 to `top`, and an
/// upper end from `step` to `top` or none (nil, the wheel's "∞"), meaning no upper limit. An
/// upper end of 0 would match no workout, so it is never one. The ends never cross: moving one
/// past the other carries the other with it. 0 to no limit is the filter off.
public struct LengthRange: Hashable, Sendable {
    public private(set) var lower: Int
    /// The upper end, nil for no upper limit.
    public private(set) var upper: Int?

    /// The wheels' highest number.
    public static let top = 90
    /// The wheels' step, and the upper end's lowest value.
    public static let step = 5
    public static let full = Self(lower: 0, upper: nil)

    /// The left wheel's values, 0 to `top`.
    public static let lowerValues = Array(stride(from: 0, through: top, by: step))
    /// The right wheel's values: `step` to `top`, then no upper limit.
    public static let upperValues: [Int?] = lowerValues.dropFirst().map(Optional.some) + [nil]

    public init(lower: Int, upper: Int?) {
        let upper = upper.map(Self.upperEnd)
        self.lower = upper.map { min(lower, $0) } ?? lower
        self.upper = upper
    }

    private static func upperEnd(_ minutes: Int) -> Int {
        max(minutes, step)
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
        upper = minutes.map(Self.upperEnd)
        if let upper {
            lower = min(lower, upper)
        }
    }

    public func contains(_ minutes: Int) -> Bool {
        minutes >= lower && upper.map { minutes <= $0 } ?? true
    }

    /// The range's words: "25–45 min", "≥ 45 min" with no upper limit, "≤ 20 min" from 0,
    /// "20 min" for one length. Both ends count, since a length is a rounded figure, so a
    /// preset reads as any range does.
    public var label: String {
        guard let upper else { return "≥ \(lower) min" }
        guard lower != 0 else { return "≤ \(upper) min" }
        guard lower != upper else { return "\(upper) min" }
        return "\(lower)–\(upper) min"
    }

    /// The range as VoiceOver reads it, for a "≤" or "≥" that reads poorly: "20 minutes or
    /// less", "40 minutes or more", "20 minutes", "25 to 45 minutes".
    public var spoken: String {
        guard let upper else { return "\(lower) minutes or more" }
        guard lower != 0 else { return "\(upper) minutes or less" }
        guard lower != upper else { return "\(upper) minutes" }
        return "\(lower) to \(upper) minutes"
    }

    /// The preset this range is, if any.
    public var preset: Preset? {
        Preset.allCases.first { $0.range == self }
    }

    public enum Preset: CaseIterable, Sendable {
        case upTo20
        case twentyToForty
        case from40

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

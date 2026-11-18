import Foundation

/// The five settings Customize sets, the same for a built-in and a created exercise: its name,
/// the muscle groups it works, the equipment it uses, how a set is measured, and whether each
/// side is its own set. Everything else an exercise has is derived from them, or shipped.
public struct ExerciseSettings: Equatable, Sendable {
    public var name: String
    public var muscleGroups: Set<MuscleGroup>
    public var equipment: Set<Equipment>
    public var measure: Measure
    public var isPerSide: Bool

    public init(
        name: String,
        muscleGroups: Set<MuscleGroup>,
        equipment: Set<Equipment> = [],
        measure: Measure = .reps,
        isPerSide: Bool = false,
    ) {
        self.name = name
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.measure = measure
        self.isPerSide = isPerSide
    }
}

extension ExerciseSettings {
    /// What differs from `original`, in the form's order: "Renamed from Barbell bench press",
    /// each group and piece of equipment added or removed ("Arms added", "Bench removed"),
    /// "Timed" or "In reps", and "Per side" or "Not per side". Empty when nothing differs.
    public func changes(from original: Self) -> [String] {
        var changes: [String] = []
        if name != original.name {
            changes.append("Renamed from \(original.name)")
        }
        changes += Self.changes(of: muscleGroups, from: original.muscleGroups)
        changes += Self.changes(of: equipment, from: original.equipment)
        if measure != original.measure {
            changes.append(measure == .time ? "Timed" : "In reps")
        }
        if isPerSide != original.isPerSide {
            changes.append(isPerSide ? "Per side" : "Not per side")
        }
        return changes
    }

    private static func changes<Element: NamedCase>(
        of set: Set<Element>,
        from original: Set<Element>,
    ) -> [String] {
        Element.allCases.compactMap { item in
            switch (set.contains(item), original.contains(item)) {
            case (true, false): "\(item.name) added"
            case (false, true): "\(item.name) removed"
            default: nil
            }
        }
    }
}

extension CreatedExercise {
    /// Its five settings, read and written over its own stored ones.
    public var settings: ExerciseSettings {
        get {
            ExerciseSettings(
                name: name,
                muscleGroups: muscleGroups,
                equipment: equipment,
                measure: measure,
                isPerSide: isPerSide,
            )
        }
        set {
            name = newValue.name
            muscleGroups = newValue.muscleGroups
            equipment = newValue.equipment
            measure = newValue.measure
            isPerSide = newValue.isPerSide
        }
    }
}

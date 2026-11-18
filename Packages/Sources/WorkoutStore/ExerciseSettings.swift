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

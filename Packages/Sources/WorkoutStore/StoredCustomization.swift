import Foundation

typealias StoredCustomization = RoutineSchemaV10.StoredCustomization

extension StoredCustomization {
    /// The customization as set. A setting this build can't read, from a newer version (an
    /// unknown measure, or muscle groups or equipment none of which it knows), reads as shipped;
    /// an unknown group or piece of equipment beside known ones is left out of its set.
    var customization: Customization {
        var changed = Set<Customization.Setting>(stored: changed)
        let groups = Set<MuscleGroup>(stored: muscleGroups)
        if groups.isEmpty != muscleGroups.isEmpty {
            changed.remove(.muscleGroups)
        }
        let equipment = Set<Equipment>(stored: equipment)
        if equipment.isEmpty != self.equipment.isEmpty {
            changed.remove(.equipment)
        }
        let measure = Measure(rawValue: measure)
        if measure == nil {
            changed.remove(.measure)
        }
        return Customization(
            exerciseID: exerciseID,
            settings: ExerciseSettings(
                name: name,
                muscleGroups: groups,
                equipment: equipment,
                measure: measure ?? .reps,
                isPerSide: isPerSide,
            ),
            changed: changed,
        )
    }

    /// Sets only the fields that changed, so an unchanged customization stays clean.
    func write(_ customization: Customization, at date: Date) {
        let settings = customization.settings
        let before = (changed, name, muscleGroups, equipment, measure, isPerSide)
        update(\.changed, to: customization.changed.stored)
        update(\.name, to: settings.name)
        update(\.muscleGroups, to: settings.muscleGroups.stored)
        update(\.equipment, to: settings.equipment.stored)
        update(\.measure, to: settings.measure.rawValue)
        update(\.isPerSide, to: settings.isPerSide)
        if before != (changed, name, muscleGroups, equipment, measure, isPerSide) {
            editedAt = date
        }
    }
}

import Foundation

/// A built-in's changes, stored apart from the catalog, which is never edited. Only the settings
/// in `changed` are someone's; every other one reads as shipped, so an app update that changes a
/// built-in still reaches every setting nobody changed. Muscle groups and equipment are changed
/// whole: if both someone and an update change one, theirs wins.
public struct Customization: Equatable, Sendable {
    /// One of the five settings, as a customization marks it changed. Raw values are stored.
    public enum Setting: String, NamedCase {
        case name
        case muscleGroups = "muscle-groups"
        case equipment
        case measure
        case perSide = "per-side"

        public var name: String {
            switch self {
            case .name: "Name"
            case .muscleGroups: "Muscle groups"
            case .equipment: "Equipment"
            case .measure: "Measure"
            case .perSide: "Per side"
            }
        }
    }

    /// The built-in's slug.
    public let exerciseID: String
    /// The settings as someone set them; only those in `changed` count.
    public let settings: ExerciseSettings
    public let changed: Set<Setting>

    public init(exerciseID: String, settings: ExerciseSettings, changed: Set<Setting>) {
        self.exerciseID = exerciseID
        self.settings = settings
        self.changed = changed
    }

    /// The changes that make `shipped` into `settings`: only the settings that differ, so one set
    /// back to how it shipped is no change at all.
    public init(of shipped: Exercise, to settings: ExerciseSettings) {
        let original = shipped.settings
        var changed = Set<Setting>()
        if settings.name != original.name {
            changed.insert(.name)
        }
        if settings.muscleGroups != original.muscleGroups {
            changed.insert(.muscleGroups)
        }
        if settings.equipment != original.equipment {
            changed.insert(.equipment)
        }
        if settings.measure != original.measure {
            changed.insert(.measure)
        }
        if settings.isPerSide != original.isPerSide {
            changed.insert(.perSide)
        }
        self.init(exerciseID: shipped.id, settings: settings, changed: changed)
    }

    /// Whether nothing is changed from how it shipped.
    public var isEmpty: Bool {
        changed.isEmpty
    }

    /// `original` with these changes made.
    func applied(to original: ExerciseSettings) -> ExerciseSettings {
        ExerciseSettings(
            name: changed.contains(.name) ? settings.name : original.name,
            muscleGroups: changed.contains(.muscleGroups)
                ? settings.muscleGroups : original.muscleGroups,
            equipment: changed.contains(.equipment) ? settings.equipment : original.equipment,
            measure: changed.contains(.measure) ? settings.measure : original.measure,
            isPerSide: changed.contains(.perSide) ? settings.isPerSide : original.isPerSide,
        )
    }
}

import Foundation

/// Names a routine from its exercises: for what they work, from their tags, in the routine's own
/// style. Written in code: Apple's on-device model, given the same tags, named routines less
/// sharply and less honestly. A pure function of the exercises and the routine's id, so a name
/// needs no storing: the same routine gets the same name again.
public struct RoutineNamer: Sendable {
    private let usesTags: Bool

    /// Longer than this, a name doesn't fit one line of the title.
    static let longestName = 20

    /// Names for what the exercises work, from their tags.
    public static let standard = Self(usesTags: true)

    /// Muscle-group names only: "Legs", "Chest and back", "Full body". The same for every
    /// routine, where `standard`'s style follows the routine's id.
    public static let muscleGroupsOnly = Self(usesTags: false)

    /// A name for these exercises, or nil for none. `routine` sets the name's style, so each
    /// routine keeps its own as its exercises change, and different routines differ.
    public func name(for exercises: [Exercise], of routine: Routine.ID) -> String? {
        let unique = Self.unique(exercises)
        guard let fallback = MuscleGroup.routineName(for: unique.map(\.muscleGroup)) else {
            return nil
        }
        guard usesTags else { return fallback }
        let focus = RoutineFocus(of: unique)
        let style = NameStyle(of: routine)
        guard let picked = style.pick(focus.names(for: unique)) else { return fallback }
        return focus.checked(picked, against: unique)
    }

    private static func unique(_ exercises: [Exercise]) -> [Exercise] {
        var seen = Set<Exercise.ID>()
        return exercises.filter { seen.insert($0.id).inserted }
    }
}

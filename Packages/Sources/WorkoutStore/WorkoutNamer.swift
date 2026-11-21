import Foundation

/// Names a workout from its exercises: for what they work, from their tags, in the workout's own
/// style. Written in code: Apple's on-device model, given the same tags, named workouts less
/// sharply and less honestly. A pure function of the exercises and the workout's id, so a name
/// needs no storing: the same workout gets the same name again.
public struct WorkoutNamer: Sendable {
    private let usesTags: Bool

    /// Longer than this, a name doesn't fit one line of the title.
    static let longestName = 20

    /// Names for what the exercises work, from their tags.
    public static let standard = Self(usesTags: true)

    /// Muscle-group names only: "Legs", "Chest and back", "Full body". The same for every
    /// workout, where `standard`'s style follows the workout's id.
    public static let muscleGroupsOnly = Self(usesTags: false)

    /// A name for these exercises, or nil for none. `workout` sets the name's style, so each
    /// workout keeps its own as its exercises change, and different workouts differ.
    public func name(for exercises: [Exercise], of workout: Workout.ID) -> String? {
        let unique = Self.unique(exercises)
        guard let fallback = MuscleGroup.workoutName(for: unique.flatMap(\.muscleGroups)) else {
            return nil
        }
        guard usesTags else { return fallback }
        let focus = WorkoutFocus(of: unique)
        let style = NameStyle(of: workout)
        guard let picked = style.pick(focus.names(for: unique)) else { return fallback }
        return focus.checked(picked, against: unique)
    }

    /// The name a workout shows: the one chosen, else the one made from its exercises, else
    /// nil for New workout.
    public func shownName(of workout: Workout) -> String? {
        workout.name.isEmpty
            ? name(for: workout.exercises.map(\.exercise), of: workout.id)
            : workout.name
    }

    private static func unique(_ exercises: [Exercise]) -> [Exercise] {
        var seen = Set<Exercise.ID>()
        return exercises.filter { seen.insert($0.id).inserted }
    }
}

/// One entry of the Workouts list under its bar: a workout's row, the Create workout row, or an
/// "Also needs" heading.
public enum WorkoutsItem: Identifiable, Sendable {
    case workout(Workout)
    case create
    case needs(Equipment)

    public enum Key: Hashable, Sendable {
        case workout(Workout.ID)
        case create
        case needs(Equipment)
    }

    public var id: Key {
        switch self {
        case let .workout(workout): .workout(workout.id)
        case .create: .create
        case let .needs(piece): .needs(piece)
        }
    }

    public var workout: Workout? {
        if case let .workout(workout) = self {
            workout
        } else {
            nil
        }
    }

    /// The matches, Create workout, then each section under its heading, as Add exercise lists
    /// its Create row: while any filter is on, the last of the matches, and the only row when
    /// nothing matches and nothing is a piece short.
    public static func items(_ filtered: FilteredWorkouts, filter: WorkoutFilter) -> [Self] {
        let create: [Self] = filter.isOn ? [.create] : []
        return filtered.matches.map(workout) + create + filtered.alsoNeeds.flatMap { section in
            [.needs(section.piece)] + section.items.map(Self.workout)
        }
    }
}

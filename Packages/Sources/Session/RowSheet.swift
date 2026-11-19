import WorkoutStore

/// A row's open sheet: which row, and whether it opens on Customize, as after Create. The flag
/// rides with the sheet's item: a separate state set with it read as unset in the sheet.
public struct RowSheet: Identifiable, Equatable {
    public let id: RoutineExercise.ID
    public var opensCustomizing: Bool

    public init(id: RoutineExercise.ID, opensCustomizing: Bool = false) {
        self.id = id
        self.opensCustomizing = opensCustomizing
    }
}

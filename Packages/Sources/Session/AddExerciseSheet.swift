import Foundation
import WorkoutStore

/// Add exercise's open sheet: the filter its list starts with. The workout screen's + opens it
/// with none; a caller that knows what is wanted, a muscle group, opens it with that chosen.
public struct AddExerciseSheet: Identifiable {
    public let filter: ExerciseFilter
    /// This opening's own identity, which the picker takes, so every opening starts from its
    /// own filter and none comes up with the last one's, as a row's sheet did
    /// (`RowSheet.opening`): filters clear when Add exercise closes.
    public let id = UUID()

    public init(filter: ExerciseFilter = ExerciseFilter()) {
        self.filter = filter
    }
}

extension AppSession {
    /// Opens Add exercise with `filter` on. The same ask while it is open keeps the opening
    /// already asked for, so a double tap doesn't build the rising sheet again.
    public func openAddExercise(filter: ExerciseFilter = ExerciseFilter()) {
        guard addExercise == nil else { return }
        addExercise = AddExerciseSheet(filter: filter)
    }

    public func closeAddExercise() {
        addExercise = nil
    }
}

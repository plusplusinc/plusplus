import Foundation
import WorkoutStore

/// Add exercise's open sheet. Its filter is not the sheet's: it is the open workout's
/// (`AppSession.addExerciseFilter`), on again at the next opening until cleared.
public struct AddExerciseSheet: Identifiable {
    /// This opening's own identity, which the picker takes, so every opening starts from fresh
    /// view state (an empty search, the top of the list, no pushed Customize) and none comes up
    /// with the last one's, as a row's sheet did (`RowSheet.opening`).
    public let id = UUID()

    public init() { }
}

extension AppSession {
    /// Opens Add exercise on the open workout's kept filter, or on `filter` when a caller that
    /// knows what is wanted hands one in: it replaces the kept one, and is kept in turn. The
    /// same ask while it is open changes nothing, so a double tap doesn't build the rising
    /// sheet again.
    public func openAddExercise(filter: ExerciseFilter? = nil) {
        guard addExercise == nil else { return }
        if let filter {
            addExerciseFilter = filter
        }
        addExercise = AddExerciseSheet()
    }

    public func closeAddExercise() {
        addExercise = nil
    }
}

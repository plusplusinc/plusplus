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
    /// Opens Add exercise on the open workout's kept filter. The same ask while it is open
    /// changes nothing, so a double tap doesn't build the rising sheet again.
    public func openAddExercise() {
        guard addExercise == nil else { return }
        addExercise = AddExerciseSheet()
    }

    /// Opens Add exercise if New asked for it as it made the workout showing (`startNew(from:)`),
    /// once: the workout screen calls it as it shows.
    public func takeAddExerciseOnShow() {
        guard opensAddExerciseOnShow else { return }
        opensAddExerciseOnShow = false
        openAddExercise()
    }

    public func closeAddExercise() {
        addExercise = nil
    }
}

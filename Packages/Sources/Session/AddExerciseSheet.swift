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
    /// once, `hold` after the workout screen has finished arriving: the new workout is seen
    /// arrive and rest before the sheet rises, which at once rose over the push and read as too
    /// quick. Nothing opens if the wait is cancelled, as when the screen goes and its task with
    /// it, or the app has shown another screen or workout (which clears the ask) or the drawer
    /// meanwhile, as a created row's sheet waits (`openRowSheet(_:after:if:)`).
    public func takeAddExerciseOnShow(after hold: Duration) async {
        guard opensAddExerciseOnShow else { return }
        let screen = screen
        let workout = opened.id
        // A sleep that had already ended when it was cancelled resumes without throwing.
        guard await (try? Task.sleep(for: hold, tolerance: .zero)) != nil, !Task.isCancelled,
              opensAddExerciseOnShow, self.screen == screen, opened.id == workout,
              !isDrawerOpen, !isDrawerHeld else { return }
        opensAddExerciseOnShow = false
        openAddExercise()
    }

    public func closeAddExercise() {
        addExercise = nil
    }
}

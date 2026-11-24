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
    /// changes nothing, so a double tap doesn't build the rising sheet again. Opened by hand, it
    /// takes the place of the opening New asked for (`takeAddExerciseOnShow(after:isTouched:)`).
    public func openAddExercise() {
        opensAddExerciseOnShow = false
        guard addExercise == nil else { return }
        addExercise = AddExerciseSheet()
    }

    /// Opens Add exercise if New asked for it as it made the workout showing (`startNew(from:)`),
    /// once, `hold` after the workout screen has finished arriving. The ask is spent however the
    /// wait ends: nothing opens if the wait is cancelled, as when the screen goes and its task
    /// with it, if the app has left that screen or workout (`stays(after:)`), if Add exercise was
    /// opened by hand meanwhile, if the drawer, a row's sheet, or an exercise came first, if the
    /// screen began to leave (`leaveBeforeAddExercise()`), or if a finger is down as the wait
    /// ends (`isTouched()`): a press of Back under way pops only as the finger lifts, so until
    /// then the screen reads as staying, and the sheet would rise and come up over the list.
    public func takeAddExerciseOnShow(after hold: Duration, isTouched: () -> Bool) async {
        guard opensAddExerciseOnShow else { return }
        let stays = await stays(after: hold)
        guard opensAddExerciseOnShow else { return }
        opensAddExerciseOnShow = false
        guard stays, !isTouched(), current.isEmpty, rowSheet == nil, !isDrawerOpen,
              !isDrawerHeld else { return }
        openAddExercise()
    }

    /// Spends New's ask to open Add exercise the moment the workout screen begins to leave, as
    /// UIKit starts a pop, ahead of the stack's binding (`popWorkout()`), which hears of it
    /// after.
    public func leaveBeforeAddExercise() {
        opensAddExerciseOnShow = false
    }

    public func closeAddExercise() {
        addExercise = nil
    }
}

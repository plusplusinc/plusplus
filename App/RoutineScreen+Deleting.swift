import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Deleting a created exercise, which takes its rows from every routine that uses it, as a few
/// beats one after the other, never two moving at once. They start as Delete's alert has gone:
/// SwiftUI runs an alert's button once the alert has faded, about 0.3 s after its fade ends
/// (measured on iOS 27), which is the first beat's rest.
///
/// 1. What showed the exercise's form closes, if anything did: a routine row's sheet goes down
///    as a sheet closes, still on the form, never its sets and reps page; a form pushed in Add
///    exercise pops back to the list. Then a rest (`addPause`).
/// 2. Where Add exercise shows, its row leaves the list and the rows below close the gap, a
///    letter heading left with no rows going with them, in one move (`listChange`); a search
///    whose only result it was narrows to Create in the same move. Then a rest.
/// 3. The open routine's rows of it leave as a row's Remove takes its row
///    (`leave(footDelay:_:)`), Start and the + going down after if none is left: seen where the
///    routine shows, above a half-height Add exercise or once a row's sheet has gone; behind a
///    full one, unseen.
///
/// The store takes the delete at once; the list and the routine take it only on their beat
/// (`RoutineSession.deleteExercise(_:weightUnit:showing:)`), so the form never empties while it
/// shows. What closes goes at once, not after the store, whose write and read back took about
/// 0.3 s on the simulator.
extension RoutineScreen {
    /// What shows the exercise's form as Delete is confirmed.
    enum DeleteClosing {
        /// Add exercise's hold menu: nothing closes; the list shows the row go.
        case nothing
        /// The form pushed inside Add exercise: back pops to the list, which then shows the row
        /// go.
        case pop(back: () -> Void)
        /// The form in a routine row's sheet: the sheet goes down, then the routine's rows go.
        case rowSheet
    }

    /// Deletes the created exercise `id` in the beats the extension's comment lists, from its
    /// alert's Delete.
    func deleteExercise(_ id: Exercise.ID, closing: DeleteClosing) async {
        let confirmed = ContinuousClock.now
        let weightUnit = WeightUnit(region: locale)
        if case .rowSheet = closing {
            session.closeRowSheet()
            let shows = confirmed + Self.exerciseSheetGone + Self.addPause
            await session.deleteExercise(id, weightUnit: weightUnit) { show in
                try? await beat(until: shows)
                // Unseen: the sheet has gone. Start and the + follow as after Remove.
                show()
                showStoredRoutine(footDelay: Self.exerciseSheetGone)
            }
            return
        }
        var shows = confirmed
        if case let .pop(back) = closing {
            back()
            shows += Self.formPopped + Self.addPause
        }
        await session.deleteExercise(id, weightUnit: weightUnit) { [shows] show in
            try? await beat(until: shows)
            // With Reduce Motion, at once: the system's list slides its rows on any animation,
            // and a list rebuilt to crossfade would lose its scroll.
            withAnimation(reduceMotion ? nil : .railChange, show)
        }
        try? await beat(until: shows + Self.listChange + Self.addPause)
        showStoredRoutine()
    }

    /// From back in Add exercise to its list having slid in under the form going.
    static let formPopped: Duration = .milliseconds(500)

    /// A row leaving Add exercise's list: the system's list takes about 0.33 s to close a gap,
    /// on `.railChange` or not (measured on iOS 27).
    static let listChange: Duration = .milliseconds(350)
}

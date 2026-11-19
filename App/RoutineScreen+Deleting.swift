import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Deleting a created exercise, which takes its rows from every routine that uses it, as a few
/// beats one after the other, each from the confirming tap, never two moving at once:
///
/// 1. The question's alert fades (`promptGone`).
/// 2. What showed the exercise's form closes, if anything did: a routine row's sheet goes down
///    as a sheet closes, still on the form, never its sets and reps page; a form pushed in Add
///    exercise pops back to the list. Then a rest (`addPause`).
/// 3. Where Add exercise shows, its row leaves the list and the rows below close the gap, a
///    letter heading left with no rows going with them, in one move (`listChange`); then a
///    rest.
/// 4. The open routine's rows of it leave as a row's Remove takes its row
///    (`leave(footDelay:_:)`): seen where the routine shows, above a half-height Add exercise or
///    once a row's sheet has gone; behind a full one, unseen.
///
/// The store takes the delete at the tap; the list and the routine take it only on their beat
/// (`RoutineSession.deleteExercise(_:weightUnit:showing:)`), so the form never empties while it
/// shows. The closing runs on its own deadline, not after the store, which can take longer than
/// the alert's fade.
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

    /// Deletes the created exercise `id` in the beats the extension's comment lists.
    func deleteExercise(_ id: Exercise.ID, closing: DeleteClosing) async {
        let confirmed = ContinuousClock.now
        let closes = confirmed + Self.promptGone
        let shows: ContinuousClock.Instant
        switch closing {
        case .nothing:
            shows = closes
        case let .pop(back):
            at(closes, back)
            shows = closes + Self.formPopped + Self.addPause
        case .rowSheet:
            at(closes) { session.closeRowSheet() }
            shows = closes + Self.exerciseSheetGone + Self.addPause
        }
        let inPicker = if case .rowSheet = closing {
            false
        } else {
            true
        }
        await session.deleteExercise(id, weightUnit: WeightUnit(region: locale)) { show in
            try? await Task.sleep(until: shows, tolerance: .zero, clock: .continuous)
            guard inPicker else {
                // Unseen: the sheet has gone. Start and the + follow as after Remove.
                show()
                return showStoredRoutine(footDelay: Self.exerciseSheetGone)
            }
            withAnimation(reduceMotion ? Self.listFade : .railChange, show)
        }
        guard inPicker else { return }
        try? await Task.sleep(
            until: shows + Self.listChange + Self.addPause,
            tolerance: .zero,
            clock: .continuous,
        )
        showStoredRoutine()
    }

    /// Runs `action` at `deadline`.
    private func at(_ deadline: ContinuousClock.Instant, _ action: @escaping () -> Void) {
        Task {
            try? await Task.sleep(until: deadline, tolerance: .zero, clock: .continuous)
            action()
        }
    }

    /// From the confirming tap to the question's alert having faded: it fades over about
    /// 0.17 s from the tap (measured on iOS 27), and a sheet asked down before it has gone
    /// moves under it.
    static let promptGone: Duration = .milliseconds(250)

    /// From back in Add exercise to its list having slid in under the form going.
    static let formPopped: Duration = .milliseconds(500)

    /// A row leaving Add exercise's list, `.railChange`'s length.
    static let listChange: Duration = .milliseconds(250)

    /// With Reduce Motion, Add exercise's list changes in a fade.
    static let listFade = Animation.easeInOut(duration: 0.25)
}

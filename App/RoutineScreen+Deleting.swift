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
///    exercise pops back to the list, then a rest (`addPause`).
/// 2. Where Add exercise shows, its row leaves the list and the rows below close the gap, a
///    letter heading left with no rows going with them, in one move (`listChange`); a search
///    whose only result it was narrows to Create in the same move.
/// 3. After a rest (`addPause`, then the store's write and read back, about 0.1 s on the
///    simulator), the open routine's rows of it leave as a row's Remove takes its row, in the
///    turn the session has them gone (`showStoredRoutine`),
///    Start and the + going down after if none is left: seen where the routine shows, above a
///    half-height Add exercise or once a row's sheet has gone; behind a full one, unseen.
///
/// The store takes the delete only once nothing shows the form, and the routine shows it as
/// soon as it is stored, so no edit lands on a routine the screen and the store disagree on.
/// From the confirming tap until it is stored, a tap on one of the exercise's rows opens
/// nothing, and its row in Add exercise adds nothing; any other row opens its own sheet, on its
/// sets and reps, and the delete lands behind it.
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
        await session.deleteExercise(id, weightUnit: WeightUnit(region: locale)) {
            let stores: ContinuousClock.Instant
            switch closing {
            case .rowSheet:
                session.closeRowSheet()
                stores = confirmed + Self.exerciseSheetGone + Self.addPause
            case let .pop(back):
                back()
                try? await beat(until: confirmed + Self.formPopped + Self.addPause)
                stores = leaveList(id)
            case .nothing:
                stores = leaveList(id)
            }
            try? await beat(until: stores)
        }
        // From a row's sheet, Start and the + follow as after its Remove.
        if case .rowSheet = closing {
            showStoredRoutine(footDelay: Self.exerciseSheetGone)
        } else {
            showStoredRoutine()
        }
        // Gone from the session's list by now, or back in it if the delete was refused.
        leavingExercise = nil
    }

    /// Takes `id`'s row out of Add exercise's list, and returns when that motion and the rest
    /// after it have ended. With Reduce Motion, at once: the system's list slides its rows on
    /// any animation, and a list rebuilt to crossfade would lose its scroll.
    private func leaveList(_ id: Exercise.ID) -> ContinuousClock.Instant {
        withAnimation(reduceMotion ? nil : .railChange) { leavingExercise = id }
        return .now + Self.listChange + Self.addPause
    }

    /// Takes up the session's routine once an exercise's change has reached the store: its rows
    /// read the new settings, or, with a Delete, leave as a removed row does; with Reduce
    /// Motion, the list crossfades to them gone. Not saved again: it is the stored routine. A
    /// Delete can leave it empty: Start and the + go down after `footDelay`, as after the row's
    /// own Remove.
    func showStoredRoutine(footDelay: Duration = .zero) {
        let stored = session.current
        guard stored != routine else { return }
        let kept = Set(stored.exercises.map(\.id))
        if reduceMotion, routine.exercises.contains(where: { !kept.contains($0.id) }) {
            withAnimation(Self.crossfadeCurve) {
                listChanges += 1
                show(stored: stored)
            }
        } else {
            withAnimation(.railChange) { show(stored: stored) }
        }
        settleFoot(after: footDelay)
    }

    /// From back in Add exercise to its list having slid in under the form going.
    static let formPopped: Duration = .milliseconds(500)

    /// A row leaving Add exercise's list: the system's list takes about 0.33 s to close a gap,
    /// on `.railChange` or not (measured on iOS 27).
    static let listChange: Duration = .milliseconds(350)
}

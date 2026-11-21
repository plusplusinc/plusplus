import DesignSystem
import SwiftUI

extension RoutineScreen {
    /// Add exercise, a + floating above the key, which opens the picker.
    var addButton: some View {
        AddExerciseButton(isEditingTitle: $isEditingTitle) { openPicker() }
    }

    /// Half up, however it opens, which puts Search within a thumb's reach; pulled up, it stays
    /// up until it closes.
    func openPicker() {
        pickerDetent = .medium
        isPicking = true
    }

    /// A tap anywhere on an empty routine, or below the last row, opens the picker, once the
    /// keyboard is down if it is up or going down, so the two never cross. One that ended the
    /// title's edit opens it only on an empty routine; below the last row it has only ended the
    /// edit (`TapPastTitle`).
    func tappedList(at location: CGPoint) {
        let isEmpty = routine.exercises.isEmpty
        guard isEmpty || location.y >= listEnd.top else { return }
        if titleTap.tap(actsAfterEdit: isEmpty) {
            openPicker()
        }
    }

    /// A touch outside the title ends its edit.
    func touchedDownOutsideTitle() {
        titleTap.touchDown(isEditingTitle ? .endingEdit : .outside)
        isEditingTitle = false
    }

    /// After `delay`, once the sheet that changed the routine has gone, brings the screen's foot
    /// in line with the exercises, in one transaction for Start and the +: rising on the rising
    /// half of the key's swap, going down on its dropping half. Read when it runs, so an add or
    /// Remove meanwhile leaves it where the routine is by then. On a deadline from the pick or
    /// Remove, not the sheet's `onDismiss`, which came about 0.6 s after either, once the sheet
    /// had visibly gone (`exerciseSheetGone`).
    func settleFoot(after delay: Duration) {
        guard routine.exercises.isEmpty != footShowsEmpty else { return }
        guard delay > .zero else { return footFollowsExercises() }
        let start = ContinuousClock.now
        Task {
            try? await Task.sleep(until: start + delay, tolerance: .zero, clock: .continuous)
            footFollowsExercises()
        }
    }

    private func footFollowsExercises() {
        let isEmpty = routine.exercises.isEmpty
        guard isEmpty != footShowsEmpty else { return }
        withAnimation(isEmpty ? .keyDrop : .keyRise) {
            footShowsEmpty = isEmpty
        }
    }

    /// From Remove in the exercise sheet to the sheet having slid away, when Start and the + go
    /// down, so the drop is seen: the sheet's top cleared the screen's bottom 0.27 to 0.3 s after
    /// Remove, and at 0.5 s, or at the sheet's `onDismiss` (0.6 s), the foot then stood still for
    /// a beat before dropping.
    static let exerciseSheetGone: Duration = .milliseconds(370)
}

/// Where the room under the last row starts, in the window's space. A class, unobserved, so
/// following it as the list scrolls redraws nothing: only a tap reads it.
final class ListEnd {
    var top: CGFloat = .infinity
}

/// Add exercise's +. While the keyboard is up, as the title is edited, it fades out, keeping its
/// place. It reads the edit through a binding, so a focus change redraws it and not the screen.
struct AddExerciseButton: View {
    @Binding var isEditingTitle: Bool
    let action: () -> Void

    var body: some View {
        Button("Add exercise", systemImage: "plus", action: action)
            .opacity(isEditingTitle ? 0 : 1)
            .allowsHitTesting(!isEditingTitle)
            .accessibilityShown(!isEditingTitle)
            .animation(.easeOut(duration: RoutineScreen.barFade), value: isEditingTitle)
    }
}

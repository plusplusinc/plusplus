import DesignSystem
import SwiftUI

extension RoutineScreen {
    /// Add exercise, a + floating above the key, which opens the picker.
    var addButton: some View {
        AddExerciseButton(isEditingTitle: $isEditingTitle) { isPicking = true }
    }

    /// A touch outside the title ends its edit, and on an empty routine its tap opens the picker
    /// only if there was no edit to end.
    func touchedDownOutsideTitle() {
        tapOpensPicker = !isEditingTitle
        isEditingTitle = false
    }

    /// After `delay`, once the sheet that changed the routine has gone, brings the screen's foot
    /// in line with the exercises, in one transaction for Start and the +: rising on the rising
    /// half of the key's swap, going down on its dropping half. Read when it runs, so an add or
    /// Remove meanwhile leaves it where the routine is by then. On a deadline from the pick or
    /// Remove, not the sheet's `onDismiss`, which came 0.6 s after either, after the sheet had
    /// visibly gone: on it the foot stood still a beat, as it did at 0.5 s after Remove.
    func settleFoot(after delay: Duration) {
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
        withAnimation(
            isEmpty
                ? .easeIn(duration: PrimaryKeyButtonStyle.swapHalf)
                : .smooth(duration: PrimaryKeyButtonStyle.swapHalf),
        ) {
            footShowsEmpty = isEmpty
        }
    }

    /// From Remove in the exercise sheet to the sheet having slid away, when Start and the + go
    /// down, so the drop is seen: the sheet's top cleared the screen's bottom 0.27 to 0.3 s after
    /// Remove, and at 0.5 s the foot then stood still for a quarter second before dropping.
    static let exerciseSheetGone: Duration = .milliseconds(370)
}

extension View {
    /// While `isEmpty`, "No exercises" mid-screen, and a tap anywhere in the empty space runs
    /// `onTap`, which opens the picker as the + does. The line fades in and out with the change
    /// that empties or fills the routine.
    func emptyRoutine(isEmpty: Bool, onTap: @escaping () -> Void) -> some View {
        overlay {
            if isEmpty {
                EmptyNote("No exercises")
                    .accessibilityIdentifier("routine.noExercises")
                    .transition(.opacity)
            }
        }
        // Alongside the title's own taps, which go on editing it.
        .simultaneousGesture(TapGesture().onEnded(onTap), isEnabled: isEmpty)
    }
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

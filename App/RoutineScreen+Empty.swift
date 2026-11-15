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
}

extension View {
    /// While `isEmpty`, "No exercises" mid-screen, and a tap anywhere in the empty space runs
    /// `onTap`, which opens the picker as the + does. The line fades in and out with the change
    /// that empties or fills the routine.
    func emptyRoutine(isEmpty: Bool, onTap: @escaping () -> Void) -> some View {
        overlay {
            if isEmpty {
                NoExercises()
                    .transition(.opacity)
            }
        }
        // Alongside the title's own taps, which go on editing it.
        .simultaneousGesture(TapGesture().onEnded(onTap), isEnabled: isEmpty)
    }
}

/// What an empty routine shows mid-screen, in place of its list: one quiet line, which takes no
/// touches, so a tap through it lands on the screen's empty space. It stays put as the keyboard
/// rises.
private struct NoExercises: View {
    var body: some View {
        Text("No exercises")
            .font(.ppButton)
            .foregroundStyle(.pp(.toDo))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .ignoresSafeArea(.keyboard)
            .accessibilityIdentifier("routine.noExercises")
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

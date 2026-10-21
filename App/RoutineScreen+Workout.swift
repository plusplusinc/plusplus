import DesignSystem
import SwiftUI
import WorkoutStore

/// A workout: Start's press, the first exercise growing into the current one, and the way back
/// to it.
extension RoutineScreen {
    /// Start stays pressed in, with a haptic, and leaves; once the first exercise is in view,
    /// scrolled to if it isn't, it grows into the current exercise.
    func start(named name: String) {
        guard !isStarting, session.workout == nil else { return }
        starts += 1
        // Held down a moment first, so the key leaves pressed in, not as it was last drawn.
        withAnimation(.snappy(duration: 0.05)) {
            isStarting = true
        } completion: {
            withAnimation(.snappy(duration: 0.3)) { isStartLeaving = true }
            guard let first = routine.exercises.first?.id, currentPlace?.isMostlyOut == true
            else { return grow(named: name) }
            withAnimation(.snappy(duration: 0.35)) {
                scrollPosition.scrollTo(id: first, anchor: .top)
            } completion: {
                grow(named: name)
            }
        }
    }

    /// Starts the workout, the first exercise growing in place to fill most of the list as the
    /// rows below step aside, and the list keeping it at the top. With Reduce Motion, the list
    /// fades out and back in changed.
    private func grow(named name: String) {
        let change = {
            session.start(routineName: name)
            if let first = routine.exercises.first?.id {
                scrollPosition.scrollTo(id: first, anchor: .top)
            }
            isStarting = false
            isStartLeaving = false
        }
        guard reduceMotion else {
            return withAnimation(.snappy(duration: 0.5), change)
        }
        withAnimation(.snappy(duration: 0.15)) {
            isFadedOut = true
        } completion: {
            withTransaction(\.disablesAnimations, true, change)
            withAnimation(.snappy(duration: 0.2)) { isFadedOut = false }
        }
    }

    /// While the current exercise is scrolled fully or mostly out of view, a floating key
    /// toward it, which scrolls back to it.
    @ViewBuilder
    var wayToCurrent: some View {
        let current = currentID.flatMap { id in routine.exercises.first { $0.id == id } }
        let place = currentPlace
        Group {
            if let current, let place, place.isMostlyOut {
                CurrentExerciseButton(name: current.exercise.name, isAbove: place.isAbove) {
                    withAnimation(.snappy(duration: 0.4)) {
                        scrollPosition.scrollTo(id: current.id, anchor: .top)
                    }
                }
                .padding(.horizontal, Spacing.xl * 2)
                .padding(.bottom, Spacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: current != nil && place?.isMostlyOut == true)
    }
}

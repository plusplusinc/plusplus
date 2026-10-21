import DesignSystem
import SwiftUI
import WorkoutStore

/// A workout: Start's press, the first exercise growing into the current one, and the way back
/// to it.
extension RoutineScreen {
    /// The exercise a workout is on: the first, as nothing is done yet.
    var currentID: RoutineExercise.ID? {
        session.workout == nil ? nil : routine.exercises.first?.id
    }

    /// The exercise after the current one, whose row stays in view under it.
    var nextID: RoutineExercise.ID? {
        routine.exercises.dropFirst().first?.id
    }

    /// How tall the current exercise's label stands: the area between the bars, the end's room
    /// included as the way back hides while it shows, less the row after it and the row's own
    /// inset above and below the label.
    var currentLabelHeight: CGFloat {
        let after = nextID == nil ? endRoom : nextRowHeight ?? endRoom
        return max(visibleHeight + wayToCurrentRoom - after - RailRowMetrics.verticalInset * 2, 0)
    }

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

    /// Starts the workout, the first exercise growing in place to fill the list but for the row
    /// after it as the rows below step aside, and the list scrolling it to the top, under the bar.
    /// With Reduce Motion, the list
    /// fades out and back in changed.
    private func grow(named name: String) {
        // The list's end lies under the first row until it grows, so a short routine has
        // nowhere to scroll it to: room under the end, while it grows, lets it reach the top.
        withTransaction(\.disablesAnimations, true) { isMakingRoom = true }
        let change = {
            session.start(routineName: name)
            if let first = routine.exercises.first?.id {
                scrollPosition.scrollTo(id: first, anchor: .top)
            }
            isStarting = false
            isStartLeaving = false
        }
        guard reduceMotion else {
            return withAnimation(.snappy(duration: 0.5), change) {
                isMakingRoom = false
            }
        }
        withAnimation(.snappy(duration: 0.15)) {
            isFadedOut = true
        } completion: {
            withTransaction(\.disablesAnimations, true, change)
            withAnimation(.snappy(duration: 0.2)) {
                isFadedOut = false
            } completion: {
                isMakingRoom = false
            }
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

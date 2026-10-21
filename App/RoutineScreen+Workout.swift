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

    /// Start in three beats, each once the last has finished: the key, pressed in, slides off
    /// the bottom with its floor; the list scrolls the first exercise to just under the bar,
    /// unless it is there already; and it grows into the current exercise. The haptic plays as
    /// the key goes down. With Reduce Motion, the list crossfades into the workout.
    func start(named name: String) {
        guard !isStartAway, session.workout == nil else { return }
        // Pressed in already: held there, so the key leaves as it was when let go.
        isStarting = true
        // The list's end lies under the first row until it grows, so a short routine has
        // nowhere to scroll it to: room under the end, out of sight, lets it reach the top. It
        // goes in ahead of the scroll: a scroll in the same transaction stops at the old end.
        withTransaction(\.disablesAnimations, true) { isMakingRoom = true }
        guard !reduceMotion else { return crossfade { begin(named: name) } }
        withAnimation(.snappy(duration: Self.keyBeat)) {
            isStartAway = true
        } completion: {
            scrollToFirst { grow(named: name) }
        }
    }

    /// Scrolls the first exercise to just under the bar, then calls `next`; at once if it is
    /// there already.
    private func scrollToFirst(then next: @escaping () -> Void) {
        guard let first = routine.exercises.first?.id,
              currentPlace?.isUnderBar(inset: RailRowMetrics.verticalInset) == false
        else { return next() }
        scrollBeat.run(to: .firstUnderBar, then: next) {
            withAnimation(.snappy(duration: Self.scrollDuration)) {
                scrollPosition.scrollTo(id: first, anchor: .top)
            }
        }
    }

    /// The first exercise grows in place into the current one, filling the list but for the row
    /// after it, as the rows below step aside.
    private func grow(named name: String) {
        withAnimation(.snappy(duration: Self.rowBeat)) {
            begin(named: name)
        } completion: {
            isMakingRoom = false
        }
    }

    /// Starts the workout, keeping the first exercise under the bar as the bars change.
    private func begin(named name: String) {
        session.start(routineName: name)
        if let first = routine.exercises.first?.id {
            scrollPosition.scrollTo(id: first, anchor: .top)
        }
        isStarting = false
    }

    /// Ends the workout with `change`, Start's three beats in reverse, once Finish's dialog is
    /// gone: the current exercise shrinks back to a resting row as the rows below close up; the
    /// list scrolls back to its top, unless it is there already; and Start rises back in. With
    /// Reduce Motion, the list crossfades back.
    func end(_ change: @escaping () -> Void) {
        guard session.workout != nil else { return }
        // Start stays out until the list is back at the top, and the room under the list's end
        // keeps the shrinking row where it is, rather than the list jumping to its new end.
        withTransaction(\.disablesAnimations, true) {
            isStartAway = true
            isMakingRoom = true
        }
        guard !reduceMotion else {
            return crossfade {
                change()
                scrollPosition.scrollTo(edge: .top)
            }
        }
        withAnimation(Self.shrink, change) {
            scrollToTop {
                withTransaction(\.disablesAnimations, true) { isMakingRoom = false }
                withAnimation(.snappy(duration: Self.keyBeat)) { isStartAway = false }
            }
        }
    }

    /// Scrolls the list to its top, then calls `next`; at once if it is there already.
    private func scrollToTop(then next: @escaping () -> Void) {
        guard !scrollBeat.isListAtTop else { return next() }
        scrollBeat.run(to: .top, then: next) {
            withAnimation(.snappy(duration: Self.scrollDuration)) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
    }

    /// With Reduce Motion, the list and Start fade out, `change` happens unseen, and they fade
    /// back in changed.
    private func crossfade(_ change: @escaping () -> Void) {
        withAnimation(.snappy(duration: 0.15)) {
            isFadedOut = true
            isStartAway = true
        } completion: {
            withTransaction(\.disablesAnimations, true, change)
            withAnimation(.snappy(duration: 0.2)) {
                isFadedOut = false
                isStartAway = false
            } completion: {
                isMakingRoom = false
            }
        }
    }

    /// Notes where the first exercise is, and ends a scroll that was taking it under the bar.
    func placeCurrent(_ place: CurrentPlace) {
        currentPlace = place
        if place.isUnderBar(inset: RailRowMetrics.verticalInset) {
            scrollBeat.reached(.firstUnderBar)
        }
    }

    /// Whether the list is scrolled to its top, within the last couple of points of a scroll's
    /// spring.
    static func isAtTop(of geometry: ScrollGeometry) -> Bool {
        geometry.contentOffset.y + geometry.contentInsets.top < 2
    }

    /// Start's beats, and the end's in reverse: the key leaving or coming back, the scroll, and
    /// the current exercise growing or shrinking.
    static let keyBeat = 0.2
    static let scrollDuration = 0.35
    static let rowBeat = 0.4
    /// The current exercise shrinking back, on a curve shaped like `.snappy`'s: a spring's
    /// completion waits out its tail, which kept the scroll after it waiting a quarter second
    /// with nothing moving.
    static let shrink = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: rowBeat)

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

/// The scroll in Start's sequence and the end's, which the next beat waits for. An animated
/// scroll's `withAnimation` completion runs at once, as the scroll is not a SwiftUI animation, so
/// the beat ends as the list arrives where it was going, or, failing that, as it stops.
final class ScrollBeat {
    /// Where a scroll in the sequence takes the list.
    enum Goal {
        /// The first exercise just under the bar, at Start.
        case firstUnderBar
        /// The list's top, as a workout ends.
        case top
    }

    /// Whether the list is scrolled to its top. Not observed: read only as a sequence begins.
    private(set) var isListAtTop = true
    private var goal: Goal?
    private var next: (() -> Void)?
    private var isAnimating = false

    /// Scrolls with `scroll` toward `goal`, then, once the list is there, calls `next`.
    func run(to goal: Goal, then next: @escaping () -> Void, _ scroll: () -> Void) {
        self.goal = goal
        self.next = next
        isAnimating = false
        scroll()
    }

    /// The list has reached `goal`.
    func reached(_ goal: Goal) {
        guard goal == self.goal else { return }
        finish()
    }

    func listMoved(isAtTop: Bool) {
        isListAtTop = isAtTop
        if isAtTop {
            reached(.top)
        }
    }

    func phaseChanged(to phase: ScrollPhase) {
        if phase == .animating {
            isAnimating = true
        } else if phase == .idle, isAnimating {
            finish()
        }
    }

    private func finish() {
        guard let next else { return }
        goal = nil
        self.next = nil
        isAnimating = false
        next()
    }
}

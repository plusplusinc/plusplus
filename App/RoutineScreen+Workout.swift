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

    /// How tall the current exercise's label stands: the list's height below the row's top,
    /// less the row after it, which ends at the list's foot, and the row's own inset above and
    /// below the label.
    var currentLabelHeight: CGFloat {
        max(roomBelow(rowTop: session.currentTop) - RailRowMetrics.verticalInset * 2, 0)
    }

    /// The list's height below a row at `rowTop`, less the row after the current one, or the
    /// end's room when there is none. The next row's room under the list is left out: it lies
    /// below the list.
    private func roomBelow(rowTop: CGFloat) -> CGFloat {
        let after = nextID == nil ? endRoom : nextRowHeight ?? endRoom
        return listHeight - rowTop - after
    }

    /// Room under a row's content: in a workout, the next exercise's row runs on to the
    /// screen's foot, its text above the home indicator, so the row after it starts out of
    /// sight.
    func foot(of id: RoutineExercise.ID) -> CGFloat {
        session.workout != nil && id == nextID ? listFoot : 0
    }

    /// Notes the next exercise's row's height, less its room under the list, which the current
    /// exercise's height leaves out.
    func measureNextRow(_ id: RoutineExercise.ID) -> (CGFloat) -> Void {
        let foot = foot(of: id)
        return { nextRowHeight = $0 - foot }
    }

    /// Start in three beats, each once the last has finished: the key, pressed in, slides off
    /// the bottom with its floor; the list scrolls, only if the first exercise is not fully in
    /// view or has too little room below it to grow, and only as far as it must; and the first
    /// exercise grows into the current one where it is. The haptic plays as the key goes down.
    /// With Reduce Motion, the list crossfades into the workout.
    func start(named name: String) {
        guard !isStartAway, session.workout == nil else { return }
        // Pressed in already: held there, so the key leaves as it was when let go.
        isStarting = true
        // The list's end lies under the first row until it grows, so a short routine may have
        // nowhere to scroll it to: room under the end, out of sight, lets it go. It goes in
        // ahead of the scroll: a scroll in the same transaction stops at the old end.
        withTransaction(\.disablesAnimations, true) { isMakingRoom = true }
        guard !reduceMotion else {
            return crossfade {
                if let scroll = placeForGrowth() {
                    scrollPosition.scrollTo(y: scroll)
                }
                begin(named: name)
            }
        }
        withAnimation(.snappy(duration: Self.keyBeat)) {
            isStartAway = true
        } completion: {
            scrollToGrow { grow(named: name) }
        }
    }

    /// Picks where the first exercise's row will sit as the current one: where it is, if it
    /// is fully in view with room below to grow; else as near there as it fits, at the bar at
    /// the highest. Returns the scroll that takes it there, or nil when it stays.
    private func placeForGrowth() -> CGFloat? {
        guard let place = currentPlace else { return nil }
        let rowTop = place.rowTop
        let highestFit = max(
            roomBelow(rowTop: 0) - RailRowMetrics.verticalInset * 2 - grownLabelFit,
            0,
        )
        let top = rowTop < 0 ? 0 : min(rowTop, highestFit)
        session.currentTop = top
        guard abs(top - rowTop) >= 1 else { return nil }
        return max(place.rowContentTop - top, 0)
    }

    /// Scrolls the first exercise to where it will grow, then, once the landing has had a beat
    /// to itself, calls `next`; at once if it is there already.
    private func scrollToGrow(then next: @escaping () -> Void) {
        guard let scroll = placeForGrowth() else { return next() }
        let landed = {
            // A pause in the sequence, by design: nothing is waited for.
            Task {
                try? await Task.sleep(for: .seconds(Self.landingHold))
                next()
            }
            return
        }
        scrollBeat.run(to: .current(top: session.currentTop), then: landed) {
            withAnimation(.snappy(duration: Self.scrollDuration)) {
                scrollPosition.scrollTo(y: scroll)
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

    /// Starts the workout. The list stays where it is.
    private func begin(named name: String) {
        session.start(routineName: name)
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

    /// Notes where the first exercise is, and ends a scroll that was taking it to where it
    /// grows.
    func placeCurrent(_ place: CurrentPlace) {
        currentPlace = place
        scrollBeat.reached(.current(top: place.rowTop))
        openOnCurrentIfDue()
    }

    /// The scroll that puts the current exercise's row where Start left it.
    private var scrollToCurrent: CGFloat? {
        currentPlace.map { max($0.rowContentTop - session.currentTop, 0) }
    }

    /// Notes the height of the area between the bars, which a relaunch waits for.
    func containerResized(_ height: CGFloat) {
        visibleHeight = height
        openOnCurrentIfDue()
    }

    /// Back in a workout after a relaunch, opens the list as Start left it, once the list has
    /// its height and the current exercise its place.
    func openOnCurrentIfDue() {
        guard opensOnCurrent, visibleHeight > 0, currentPlace?.shown ?? 0 > 0,
              let scroll = scrollToCurrent else { return }
        opensOnCurrent = false
        scrollPosition.scrollTo(y: scroll)
    }

    /// The first exercise's label as it will grow at Start, unseen, measured at its own height:
    /// the least the current exercise needs.
    @ViewBuilder
    func grownLabelProbe(_ item: RoutineExercise) -> some View {
        if session.workout == nil, item.id == routine.exercises.first?.id {
            RowLabel(
                title: item.exercise.name,
                detail: item.detailParts(locale: locale),
                focus: item.focus(
                    inSuperset: routine.isInSuperset(item.id),
                    minHeight: 0,
                    locale: locale,
                ),
            )
            .hidden()
            .accessibilityHidden(true)
            .reportingHeight(true) { grownLabelFit = $0 }
        }
    }

    /// Start's beats, and the end's in reverse: the key leaving or coming back, the scroll, and
    /// the current exercise growing or shrinking.
    static let keyBeat = 0.2
    static let scrollDuration = 0.35
    static let rowBeat = 0.4
    /// The pause between a scroll landing at Start and the row growing.
    static let landingHold = 0.2
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
                        if let scroll = scrollToCurrent {
                            scrollPosition.scrollTo(y: scroll)
                        }
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
    enum Goal: Equatable {
        /// The current exercise's row this far below the bar, at Start.
        case current(top: CGFloat)
        /// The list's top, as a workout ends.
        case top
    }

    /// How far the list is scrolled. Not observed: read only as a sequence begins.
    private(set) var scrolledY: CGFloat = 0
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

    /// Whether the list is at its top, within the last couple of points of a scroll's spring.
    var isListAtTop: Bool {
        scrolledY < 2
    }

    /// The list has reached `goal`, within the last couple of points of a scroll's spring,
    /// which are no reason to wait.
    func reached(_ goal: Goal) {
        switch (goal, self.goal) {
        case (.top, .top):
            finish()
        case let (.current(top), .current(goal)) where abs(top - goal) < 2:
            finish()
        default:
            break
        }
    }

    func listMoved(to scrolledY: CGFloat) {
        self.scrolledY = scrolledY
        if isListAtTop {
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

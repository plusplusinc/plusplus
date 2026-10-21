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

    /// Whether Start shows: with exercises to start, and out of a workout but for its going.
    var showsStart: Bool {
        !routine.exercises.isEmpty && !isStartAway && (session.workout == nil || isStarting)
    }

    /// How tall the current exercise's label stands, wherever the list is scrolled: with its
    /// row just under the bar, the row fills the screen below it but for the row after it,
    /// or the end's room when there is none, and the row's own inset above and below the
    /// label. The screen runs on past the list, under the home indicator, so the next row ends
    /// at the screen's edge and the row after it starts out of sight.
    var currentLabelHeight: CGFloat {
        let after = nextID == nil ? endRoom : nextRowHeight ?? endRoom
        return max(listHeight + listFoot - after - RailRowMetrics.verticalInset * 2, 0)
    }

    /// Start's press: the key comes back up as any key does, a +1 pops off it with a medium
    /// impact (`primaryKeyBar`), and after a beat `leave(named:)` runs. A second press in the
    /// meantime does nothing.
    func pressStart() {
        guard !isStarting, !isStartAway, session.workout == nil else { return }
        // The list's end lies under the first row until it grows, so a short routine may have
        // nowhere to scroll it to: room under the end, out of sight, lets it go. It goes in
        // ahead of the scroll: a scroll in the same transaction stops at the old end. Where the
        // end showed above Start, the room would raise the edge effect's band under it.
        withTransaction(\.disablesAnimations, true) {
            isMakingRoom = true
            isBottomEdgeHidden = isEndInView
        }
        isStarting = true
    }

    /// The beat after Start's press, for its +1, then the key leaves. Run as `isStarting`
    /// changes, so the beat is cancelled if the screen goes away, and nothing has changed.
    func holdStart(named name: String) async {
        guard isStarting, session.workout == nil else { return }
        do {
            try await Task.sleep(for: .seconds(Self.pressHold))
        } catch {
            isStarting = false
            isMakingRoom = false
            isBottomEdgeHidden = false
            return
        }
        leave(named: name)
    }

    /// Start in beats, each once the last has finished: if the first exercise is scrolled
    /// mostly out of view, the list scrolls to its top and holds a moment; then the first
    /// exercise grows into the current one as the list scrolls it up under the bar, in one
    /// motion, and the key rides down off the screen with the rows below it. With Reduce
    /// Motion, the list crossfades into the workout.
    private func leave(named name: String) {
        guard !reduceMotion else {
            return crossfade {
                begin(named: name)
                isStarting = false
                scrollToCurrent()
            }
        }
        bringFirstIntoView { grow(named: name) }
    }

    /// Scrolls the list to its top if the first exercise is mostly out of view, then, once
    /// the landing has had a beat to itself, calls `next`; at once if it is in view.
    private func bringFirstIntoView(then next: @escaping () -> Void) {
        guard currentPlace?.isMostlyOut == true else { return next() }
        let landed = {
            // A pause in the sequence, by design: nothing is waited for.
            Task {
                try? await Task.sleep(for: .seconds(Self.landingHold))
                next()
            }
            return
        }
        scrollToTop(then: landed)
    }

    /// The first exercise grows into the current one as the list scrolls it up under the bar,
    /// one motion on one curve, the rows below stepping aside and Start riding down with them,
    /// as far and as fast, until it is gone. An animated scroll held the growth back until it
    /// had nearly landed, so the list is scrolled at once and drawn where it was, then both run
    /// in one animation.
    private func grow(named name: String) {
        var drop: CGFloat = 0
        if let place = currentPlace {
            let target = max(place.rowContentTop, 0)
            let lift = target - scrollBeat.scrolledY
            // The rows below move down by what the current exercise gains, less the lift.
            drop = currentLabelHeight - place.height - lift
            withTransaction(\.disablesAnimations, true) {
                growthLift = lift
                scrollPosition.scrollTo(y: target)
            }
        }
        withAnimation(.snappy(duration: Self.growBeat)) {
            begin(named: name)
            growthLift = 0
            startDrop = max(drop, 1)
            isBottomEdgeHidden = true
        } completion: {
            withTransaction(\.disablesAnimations, true) {
                isStartAway = true
                isStarting = false
                startDrop = 0
                isMakingRoom = false
                isBottomEdgeHidden = false
            }
        }
    }

    /// Starts the workout.
    private func begin(named name: String) {
        session.start(routineName: name)
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
        scrollBeat.run(then: next) {
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
                isBottomEdgeHidden = false
            }
        }
    }

    /// Notes where the first exercise is, which a relaunch waits for.
    func placeCurrent(_ place: CurrentPlace) {
        currentPlace = place
        openOnCurrentIfDue()
    }

    /// Scrolls the current exercise's row up to just under the bar.
    func scrollToCurrent() {
        if let place = currentPlace {
            scrollPosition.scrollTo(y: max(place.rowContentTop, 0))
        }
    }

    /// Notes the height of the area between the bars, which a relaunch waits for.
    func containerResized(_ height: CGFloat) {
        visibleHeight = height
        openOnCurrentIfDue()
    }

    /// Back in a workout after a relaunch, opens the list on the current exercise, once the
    /// list has its height and the current exercise its place.
    func openOnCurrentIfDue() {
        guard opensOnCurrent, visibleHeight > 0, currentPlace?.shown ?? 0 > 0 else { return }
        opensOnCurrent = false
        scrollToCurrent()
    }

    /// Start's beats, and the end's in reverse: the key leaving or coming back, the scroll, and
    /// the current exercise growing or shrinking.
    static let keyBeat = 0.2
    /// The beat between Start's press and its leaving, for its +1: the scratch app's beat after
    /// a logged set.
    static let pressHold = 0.75
    static let scrollDuration = 0.35
    /// The first exercise growing at Start, the rows below stepping aside.
    static let growBeat = 0.55
    static let rowBeat = 0.4
    /// The pause between Start's scroll to the top landing and the row growing.
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
                    withAnimation(.snappy(duration: 0.4), scrollToCurrent)
                }
                .padding(.horizontal, Spacing.xl * 2)
                .padding(.bottom, Spacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: current != nil && place?.isMostlyOut == true)
    }
}

/// The scroll to the list's top in Start's sequence and the end's, which the next beat waits
/// for. An animated scroll's `withAnimation` completion runs at once, as the scroll is not a
/// SwiftUI animation, so the beat ends as the list arrives at its top, or, failing that, as it
/// stops.
final class ScrollBeat {
    /// How far the list is scrolled. Not observed: read only as a sequence begins.
    private(set) var scrolledY: CGFloat = 0
    private var next: (() -> Void)?
    private var isAnimating = false

    /// Scrolls with `scroll` toward the list's top, then, once it is there, calls `next`.
    func run(then next: @escaping () -> Void, _ scroll: () -> Void) {
        self.next = next
        isAnimating = false
        scroll()
    }

    /// Whether the list is at its top, within the last couple of points of a scroll's spring,
    /// which are no reason to wait.
    var isListAtTop: Bool {
        scrolledY < 2
    }

    func listMoved(to scrolledY: CGFloat) {
        self.scrolledY = scrolledY
        if isListAtTop {
            finish()
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
        self.next = nil
        isAnimating = false
        next()
    }
}

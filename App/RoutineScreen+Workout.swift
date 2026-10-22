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
    /// or the end's room when there is none, its own space above, and its inset above and below
    /// the label. The screen runs on past the list, under the home indicator, so the next row
    /// ends at the screen's edge and the row after it starts out of sight.
    var currentLabelHeight: CGFloat {
        let after = nextID == nil ? endRoom : nextRowHeight ?? endRoom
        return max(
            listHeight + listFoot - after - RailRowMetrics.verticalInset * 2 - Self.currentTopSpace,
            0,
        )
    }

    /// How tall the current exercise's label stands with the row after it, or the end's room when
    /// there is none, as `currentLabelHeight` has it, worked out from `screen`, the list's frame,
    /// in the pass that lays the list out.
    func currentStanding(_ screen: GeometryProxy) -> RowStanding {
        let next = routine.exercises.dropFirst().first
        let height = screen.size.height + screen.safeAreaInsets.bottom
            - RailRowMetrics.verticalInset * 2 - Self.currentTopSpace - (next == nil ? endRoom : 0)
        return RowStanding(height: height, next: next.map {
            .init(title: $0.exercise.name, detail: $0.detailParts(locale: locale))
        })
    }

    /// The current exercise's own space above its label, part of its row, so where the list
    /// lands on the row, just under the bar, everything above it is under the bar and the space
    /// between shows only the background.
    static let currentTopSpace = Spacing.lg

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
            startDrop = 0
        }
        isStarting = true
    }

    /// The beat after Start's press, for its +1, then the key leaves. Run as `isStarting`
    /// changes, so the beat is cancelled if the screen goes away, and nothing has changed.
    func holdStart(named name: String) async {
        guard isStarting, session.workout == nil else { return }
        do {
            try await Task.sleep(for: .seconds(Self.pressHold), tolerance: .zero)
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
            return crossfade(scrollingTo: currentPlace?.landingY ?? scrollBeat.scrolledY) {
                session.start(routineName: name)
                isStarting = false
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
                try? await Task.sleep(for: .seconds(Self.landingHold), tolerance: .zero)
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
            let target = place.landingY
            let lift = target - scrollBeat.scrolledY
            // The rows below move down by what the current exercise gains, its space above
            // included, less the lift.
            drop = currentLabelHeight + Self.currentTopSpace - place.height - lift
            withTransaction(\.disablesAnimations, true) {
                growthLift = lift
                scrollPosition.scrollTo(y: target)
            }
        }
        withAnimation(.snappy(duration: Self.growBeat)) {
            session.start(routineName: name)
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

    /// Ends the workout with `change`, Start's grow in reverse, in one motion: the current
    /// exercise shrinks back to a resting row as the rows below close up, and the list scrolls
    /// back to its top. Once that lands, Start comes up on its own from below the screen's edge
    /// with its edge band, a short beat with no overshoot. The scroll is animated, not lifted
    /// as at Start: drawn lifted at the top, the title showed over the status bar, with no edge
    /// effect under the bar. On `.smooth`, the grow's curve without its bounce. With Reduce
    /// Motion, the list crossfades, then Start fades in.
    func end(_ change: @escaping () -> Void) {
        guard session.workout != nil else { return }
        // Start stays away until the list has landed, after a relaunch into a workout as well.
        withTransaction(\.disablesAnimations, true) { isStartAway = true }
        guard !reduceMotion else {
            return crossfade(scrollingTo: 0, then: bringStartBack, change)
        }
        // Room under the list's end, so the shrinking content doesn't pull the scroll up.
        withTransaction(\.disablesAnimations, true) {
            isMakingRoom = true
            isBottomEdgeHidden = true
        }
        withAnimation(.smooth(duration: Self.growBeat)) {
            change()
            scrollPosition.scrollTo(edge: .top)
        } completion: {
            withTransaction(\.disablesAnimations, true) { isMakingRoom = false }
        }
        // Start comes back as the list lands, a beat in the sequence by design: the
        // animation's completion, even logically complete, ran a third of a second after the
        // rows had settled.
        Task {
            try? await Task.sleep(for: .seconds(Self.growBeat), tolerance: .zero)
            bringStartBack()
        }
    }

    /// Start, away for the end of a workout, coming back with its edge band.
    private func bringStartBack() {
        withAnimation(.smooth(duration: Self.startReturn)) {
            isStartAway = false
            isBottomEdgeHidden = false
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

    /// With Reduce Motion, one crossfade: the list as it was fades out where it shows while the
    /// list changed by `change`, scrolled to `y`, fades in over it, as Start fades out if it
    /// goes; `then` runs once the fade has finished. The changed list is a new view, so the old
    /// one stays on screen as it fades: faded out first and in after, the screen showed empty
    /// between. The old one is drawn lifted by as far as the scroll jumps, so it holds still,
    /// with what was under the bar cut away (`TopClip`): scrolled to the top, the bar has no
    /// edge effect, and it showed through.
    private func crossfade(
        scrollingTo y: CGFloat,
        then: (() -> Void)? = nil,
        _ change: @escaping () -> Void,
    ) {
        let from = scrollBeat.scrolledY
        withTransaction(\.disablesAnimations, true) {
            isCrossfading = true
            growthLift = y - from
            underBarCut = max(from - y, 0)
            scrollPosition.scrollTo(y: y)
        }
        // The change on a later turn of the run loop, once the list going out has been drawn
        // lifted and cut: in the same update, it went out with neither.
        Task {
            withAnimation(.easeInOut(duration: Self.crossfadeDuration)) {
                listChanges += 1
                growthLift = 0
                underBarCut = 0
                change()
            } completion: {
                withTransaction(\.disablesAnimations, true) {
                    isCrossfading = false
                    isMakingRoom = false
                    isBottomEdgeHidden = false
                }
                then?()
            }
        }
    }

    /// Notes where the first exercise is, which a relaunch waits for. In a workout, where the
    /// list was landed on it and what is above it changes height, as after a text size change
    /// or a rename to a longer name, the list lands on it again: the title's text view settles
    /// its height a pass after the rest, so one landing as the change came in fell short.
    func placeCurrent(_ place: CurrentPlace) {
        let old = currentPlace
        currentPlace = place
        if let old, currentID != nil, !isScrollingByHand, place.contentTop != old.contentTop,
           abs(scrollBeat.scrolledY - old.landingY) < 1
        {
            scrollToCurrent()
        }
        openOnCurrentIfDue()
    }

    /// Scrolls the current exercise's row up to just under the bar.
    func scrollToCurrent() {
        if let place = currentPlace {
            scrollPosition.scrollTo(y: place.landingY)
        }
    }

    /// Back in a workout after a relaunch, opens the list on the current exercise, once it has
    /// its place in a list with a height. Wherever the row is: at the largest text sizes, the
    /// equipment under the title can leave it below the screen.
    func openOnCurrentIfDue() {
        guard opensOnCurrent, currentPlace?.isLaidOut == true else { return }
        opensOnCurrent = false
        scrollToCurrent()
    }

    /// The beat between Start's press and its leaving, for its +1, which overlaps the grow. The
    /// workout's first frame takes a few more to draw, so the rows move about 0.5 s after the
    /// press.
    static let pressHold = 0.4
    static let scrollDuration = 0.35
    /// The first exercise growing at Start, the rows below stepping aside, and shrinking back
    /// at the end.
    static let growBeat = 0.55
    /// Start coming back once the end's shrink has landed.
    static let startReturn = 0.25
    /// With Reduce Motion, the list crossfading into a workout or out of one.
    static let crossfadeDuration = 0.35
    /// The pause between Start's scroll to the top landing and the row growing.
    static let landingHold = 0.2

    /// While the current exercise is scrolled fully or mostly out of view, a floating key
    /// toward it, which scrolls back to it.
    @ViewBuilder
    var wayToCurrent: some View {
        let current = session.workout == nil ? nil : routine.exercises.first
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

/// The scroll to the list's top in Start's sequence, which the next beat waits for. An animated
/// scroll's `withAnimation` completion runs at once, as the scroll is not a SwiftUI animation,
/// so the beat ends as the scroll stops. Not before: a scroll set while the spring still settles
/// around the top, a point or two either side of it, is undone by it, which left the current
/// exercise where it was at Start whenever the scroll was long enough to still be settling.
final class ScrollBeat {
    /// How far the list is scrolled. Not observed: read only as a sequence begins.
    private(set) var scrolledY: CGFloat = 0
    private var next: (() -> Void)?

    /// Scrolls with `scroll` toward the list's top, then, once it has stopped, calls `next`.
    func run(then next: @escaping () -> Void, _ scroll: () -> Void) {
        self.next = next
        scroll()
    }

    /// Whether the list is at its top, so there is nothing to scroll.
    var isListAtTop: Bool {
        scrolledY < 0.5
    }

    func listMoved(to scrolledY: CGFloat) {
        self.scrolledY = scrolledY
    }

    func phaseChanged(to phase: ScrollPhase) {
        guard phase == .idle, let next else { return }
        self.next = nil
        next()
    }
}

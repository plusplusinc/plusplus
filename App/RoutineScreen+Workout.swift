import DesignSystem
import SwiftUI
import WorkoutStore

/// A workout: Start's press, the first exercise growing into the current one, and the way back
/// to it.
extension RoutineScreen {
    /// The exercise a workout is on: the row of the set it does next. None once every set is
    /// logged.
    var currentExercise: RoutineExercise? {
        currentSet.flatMap { set in routine.exercises.first { $0.id == set.row } }
    }

    var currentID: RoutineExercise.ID? {
        currentExercise?.id
    }

    /// The set a workout does next, the first in the routine's order not yet logged, as the screen
    /// shows it: none while a move to another exercise is on its way, until the next one grows.
    var currentSet: PlannedSet? {
        guard exerciseMove?.isGrowing != false else { return nil }
        return session.workout.flatMap { routine.nextSet(after: $0.sets) }
    }

    /// Whether every planned set of the workout is logged, so the Finish row ends the list.
    var isWorkoutDone: Bool {
        guard let workout = session.workout, !routine.exercises.isEmpty else { return false }
        return routine.nextSet(after: workout.sets) == nil
    }

    /// The current exercise as it grows into `set`: at a superset round's end, it shows the round
    /// just done until the move rolls it to the new one.
    func focus(of item: RoutineExercise, on set: PlannedSet) -> RowFocus {
        var focus = item.focus(on: set, inSuperset: routine.isInSuperset(item.id), locale: locale)
        if let held = exerciseMove?.heldProgress {
            focus.progress = held
        }
        return focus
    }

    /// The slide for `set`: "Log last set" on the workout's last planned set, "Log left" or "Log
    /// right" on a side, with a lighter haptic, and otherwise "Log set". Never the next exercise's
    /// name, which shows below.
    func logStep(_ set: PlannedSet, of item: RoutineExercise) -> LogStep {
        let action = { log(set, of: item) }
        let weight: SlideToLog.Weight = set.side == nil ? .set : .side
        let isLast = session.workout.map {
            routine.nextSet(after: $0.logging(set, of: item, at: .now).sets) == nil
        } ?? false
        let label = switch (isLast, set.side) {
        case (true, _): String(localized: "Log last set")
        case (false, .left): String(localized: "Log left")
        case (false, .right): String(localized: "Log right")
        case (false, nil): String(localized: "Log set")
        }
        return LogStep(label: label, weight: weight, action: action)
    }

    /// The rows whose sets are all logged in the workout, whose nodes show them done.
    var finishedRows: Set<RoutineExercise.ID> {
        guard let sets = session.workout?.sets else { return [] }
        return Set(routine.exercises.lazy.map(\.id).filter { id in
            let progress = routine.progress(of: id, logged: sets)
            return progress.total > 0 && progress.done == progress.total
        })
    }

    /// The set bars a row shows in a workout: on the current exercise always, from its first set;
    /// on any other only once started and until finished, where its node shows it done.
    func bars(of id: RoutineExercise.ID) -> SetProgress? {
        guard let sets = session.workout?.sets else { return nil }
        let progress = routine.progress(of: id, logged: sets)
        guard id == currentID
            || routine.isStarted(id, logged: sets) && progress.done < progress.total
        else { return nil }
        return SetProgress(
            done: progress.done,
            total: progress.total,
            spoken: spokenProgress(done: progress.done, total: progress.total, locale: locale),
        )
    }

    /// The row that grows, or stands grown: the current exercise, or, out of a workout, the
    /// first, which Start grows.
    var growingID: RoutineExercise.ID? {
        session.workout == nil ? routine.exercises.first?.id : currentID
    }

    /// The row after `id` in the list, if any.
    func row(after id: RoutineExercise.ID?) -> RoutineExercise? {
        guard let index = routine.exercises.firstIndex(where: { $0.id == id }) else { return nil }
        return routine.exercises.dropFirst(index + 1).first
    }

    /// Logs the set the slide was on, at the numbers its row shows. Within one exercise the
    /// progress line rolls to the next set. Moving to another, in `SetMotion`'s beats, each a
    /// little over the last: the current row shrinks back to a resting row; a green pulse travels
    /// along the rail to the next row's node, round a superset's loop at a round's end, as the
    /// list scrolls the next row up under the bar; and the next row grows into the current
    /// exercise as the pulse lands. The scroll is Start's: the list is scrolled at once to where
    /// the next row will land and drawn where it was, the lift run to 0 on the pulse's curve.
    /// After the last set, the row shrinks and the Finish row shows under it.
    func log(_ set: PlannedSet, of row: RoutineExercise) {
        guard let workout = session.workout else { return }
        let next = routine.nextSet(after: workout.logging(set, of: row, at: .now).sets)
        guard next?.row != set.row else {
            withAnimation(.snappy(duration: SetMotion.roll)) { session.log(set, of: row) }
            return
        }
        guard let next else { return logLast(set, of: row) }
        let target = landing(on: next.row, leaving: row.id)
        noteRestingPitch(of: next.row)
        guard !reduceMotion else {
            return crossfade(scrollingTo: target ?? scrollBeat.scrolledY) {
                session.log(set, of: row)
            }
        }
        let rows = routine.exercises.map(\.id)
        let isUp = (rows.firstIndex(of: next.row) ?? 0) < (rows.firstIndex(of: row.id) ?? 0)
        // At a superset round's end, the round just done rolls to the next as the first grows.
        let held = isUp && next.round != set.round && routine.isInSuperset(next.row)
            ? focus(of: row, on: set).progress : nil
        isMovingOn = true
        if let target {
            withTransaction(\.disablesAnimations, true) {
                isMakingRoom = true
                growthLift = target - scrollBeat.scrolledY
                scrollPosition.scrollTo(y: target)
            }
            withAnimation(SetMotion.scroll(up: isUp)) { growthLift = 0 }
        }
        withAnimation(.snappy(duration: SetMotion.shrink)) {
            exerciseMove = ExerciseMove(to: next.row, heldProgress: held)
            railPulse = RailPulse(from: row.id, to: next.row, run: (railPulse?.run ?? 0) + 1)
            session.log(set, of: row)
        }
        // The beats after the shrink, timed from the log by design: nothing is waited for.
        Task {
            try? await Task.sleep(for: .seconds(SetMotion.growStart), tolerance: .zero)
            withAnimation(.snappy(duration: SetMotion.grow)) { exerciseMove?.isGrowing = true }
            if held != nil {
                try? await Task.sleep(for: .seconds(SetMotion.roundRoll), tolerance: .zero)
                withAnimation(.snappy(duration: SetMotion.roll)) { exerciseMove?.heldProgress = nil
                }
            }
            try? await Task.sleep(for: .seconds(SetMotion.grow), tolerance: .zero)
            exerciseMove = nil
            isMovingOn = false
            letRoomGo()
            // With no landing worked out ahead, as after a relaunch, the list lands after.
            if target == nil {
                withAnimation(.snappy(duration: SetMotion.grow), scrollToCurrent)
            }
        }
    }

    /// The workout's last planned set: the row shrinks back, then the list's room to land a
    /// current exercise goes as the list settles on its end, the Finish row under the last row.
    private func logLast(_ set: PlannedSet, of row: RoutineExercise) {
        isMovingOn = true
        withAnimation(.snappy(duration: SetMotion.shrink)) {
            session.log(set, of: row)
        } completion: {
            withAnimation(.snappy(duration: SetMotion.settle)) {
                isMovingOn = false
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    /// Finishes the workout from the Finish row, at once, with no dialog, as End's Finish does.
    func finish(named name: String) {
        end { session.finish(routineName: name) }
    }

    /// Where the list lands `next`'s row under the bar once `leaving`, the current row, has
    /// shrunk back: at the row's top, where its label lands just under the bar. A row above
    /// stays where it is; one below rises by what `leaving` gives back, from its pitch now, top
    /// to the next row's top, to its pitch at rest, noted as it grew. Nil when either isn't
    /// known, as after a relaunch into a workout.
    private func landing(on next: RoutineExercise.ID, leaving: RoutineExercise.ID) -> CGFloat? {
        guard let nextTop = rowFrames.tops[next], let leavingTop = rowFrames.tops[leaving]
        else { return nil }
        guard nextTop > leavingTop else { return max(nextTop, 0) }
        guard let after = row(after: leaving).flatMap({ rowFrames.tops[$0.id] }),
              let resting = rowFrames.restingPitch[leaving]
        else { return nil }
        return max(nextTop - (after - leavingTop - resting), 0)
    }

    /// Notes `id`'s pitch at rest, top to the next row's top, before it grows: what it gives
    /// back as it shrinks. The rail keeps a resting row to a rhythm, so it is more than its height.
    func noteRestingPitch(of id: RoutineExercise.ID?) {
        guard let id, let top = rowFrames.tops[id],
              let after = row(after: id).flatMap({ rowFrames.tops[$0.id] })
        else { return }
        rowFrames.restingPitch[id] = after - top
    }

    /// Whether Start shows: with exercises to start, and out of a workout but for its going.
    var showsStart: Bool {
        !routine.exercises.isEmpty && !isStartAway && (session.workout == nil || isStarting)
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
    /// one motion on one curve, the rows below stepping aside and Start riding down off the
    /// screen as they do. An animated scroll held the growth back until it
    /// had nearly landed, so the list is scrolled at once and drawn where it was, then both run
    /// in one animation.
    private func grow(named name: String) {
        noteRestingPitch(of: routine.exercises.first?.id)
        // The grown exercise's height is its content's, known once it is laid out, so Start rides
        // a screen's height down, out of sight by the time the growth ends.
        let drop = listHeight
        if let place = currentPlace {
            let target = place.landingY
            let lift = target - scrollBeat.scrolledY
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
                isBottomEdgeHidden = false
            }
            letRoomGo()
        }
    }

    /// Takes away the screen's room under the list's end once Start or a move to the next
    /// exercise is over. The room to land the current exercise under the bar
    /// (`roomToLand(top:visible:)`) stays, worked out in each layout pass, so it holds the list
    /// wherever the growth is.
    func letRoomGo() {
        guard isMakingRoom, !isStarting, !isMovingOn, session.workout != nil else { return }
        withTransaction(\.disablesAnimations, true) { isMakingRoom = false }
    }

    /// Ends the workout with `change`, Start's grow in reverse, in one motion: the current
    /// exercise shrinks back to a resting row as the rows below close up, and the list scrolls
    /// back to its top. Once that lands, Start comes up on its own from below the screen's edge
    /// with its edge band, a short beat with no overshoot. The scroll is animated, not lifted
    /// as at Start: drawn lifted at the top, the title showed over the status bar, with no edge
    /// effect under the bar. On a curve that eases out and stops at its duration: a spring's
    /// settling tail made the end feel slow and heavy as it landed. With Reduce Motion, the list
    /// crossfades, then Start fades in.
    func end(_ change: @escaping () -> Void) {
        guard let workout = session.workout else { return }
        withTransaction(\.disablesAnimations, true) {
            endingWorkout = workout
            // Start stays away until the list has landed, after a relaunch into a workout too.
            isStartAway = true
        }
        // Once the time has faded out of its key, the key's glass goes, the bar fading it: taken
        // out with no animation, it went on the frame. A beat in the sequence by design.
        Task {
            try? await Task.sleep(for: .seconds(Self.barFade), tolerance: .zero)
            withAnimation(.easeOut(duration: Self.barFade)) { endingWorkout = nil }
        }
        guard !reduceMotion else {
            return crossfade(scrollingTo: 0, then: bringStartBack, change)
        }
        // Room under the list's end, so the shrinking content doesn't pull the scroll up.
        withTransaction(\.disablesAnimations, true) {
            isMakingRoom = true
            isBottomEdgeHidden = true
        }
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: Self.endBeat)) {
            change()
            scrollPosition.scrollTo(edge: .top)
        } completion: {
            withTransaction(\.disablesAnimations, true) { isMakingRoom = false }
        }
        // Start comes back as the list lands, a beat in the sequence by design: the animation's
        // completion came a few frames after the rows had stopped.
        Task {
            try? await Task.sleep(for: .seconds(Self.endBeat), tolerance: .zero)
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
                    isBottomEdgeHidden = false
                }
                letRoomGo()
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
        letRoomGo()
        // Not while moving to the next exercise, which lands it: its place, read as it grows,
        // is on the way there.
        if let old, currentID != nil, !isScrollingByHand, !isMovingOn,
           place.contentTop != old.contentTop,
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
    /// The first exercise growing at Start, the rows below stepping aside.
    static let growBeat = 0.55
    /// The current exercise shrinking back at the end, the rows below closing up, on a curve
    /// quick off the mark that eases gently into place and stops at its duration, with no
    /// spring's tail.
    static let endBeat = 0.4
    /// The bar's keys fading at a workout's end: End for ++, and the time out of its key, then
    /// the key's glass.
    static let barFade = 0.2
    /// Start coming back once the end's shrink has landed.
    static let startReturn = 0.2
    /// With Reduce Motion, the list crossfading into a workout or out of one.
    static let crossfadeDuration = 0.35
    /// The pause between Start's scroll to the top landing and the row growing.
    static let landingHold = 0.2

    /// While the current exercise is scrolled fully or mostly out of view, a floating key
    /// toward it, which scrolls back to it.
    @ViewBuilder
    var wayToCurrent: some View {
        let current = currentExercise
        let place = currentPlace
        Group {
            // Not while the list moves to the next exercise, whose row passes through the edge.
            if let current, let place, place.isMostlyOut, !isMovingOn {
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

/// A move from one exercise to the next in progress, from the log until the next has grown.
struct ExerciseMove {
    /// The row it moves to, whose space above opens as the last one shrinks, so the travel lands
    /// its label where it stays as it grows.
    let to: RoutineExercise.ID
    /// Whether the next exercise has started to grow, its set shown.
    var isGrowing = false
    /// At a superset round's end, the round just done, which the first member shows as it starts
    /// to grow, then rolls to its own.
    var heldProgress: String?
}

/// Where each row is in the list's content, and each row's height when last at rest, read as
/// a move begins. Not observed: rows report as they lay out, and redrawing the screen for each
/// would redraw it on every frame of a move.
final class RowFrames {
    var tops: [RoutineExercise.ID: CGFloat] = [:]
    var restingPitch: [RoutineExercise.ID: CGFloat] = [:]
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

import DesignSystem
import SwiftUI
import WorkoutStore

/// A workout: Start's press, and the first exercise growing into the current one.
extension RoutineScreen {
    /// The current exercise's own space above its label, part of its row, so where the list
    /// lands on the row, just under the bar, everything above it is under the bar and the space
    /// between shows only the background.
    static let currentTopSpace = Spacing.lg

    /// From Start's press until the first exercise has grown: the key is Start's.
    var isStarting: Bool {
        phase.isStarting
    }

    /// Start's press: the key comes back up as any key does, a medium impact plays, and after a
    /// beat the first exercise is brought into view and grows (`leave()`), one sequence on the
    /// screen's task, which the screen going away stops. A second press in the meantime does
    /// nothing. The press leaves the drawer open, as Dave decided (2026-11-14): a routine
    /// switched to before the workout begins stops Start's beats (`check(_:)`), and the session
    /// starts a workout only on the routine pressed (`RoutineSession.start(on:at:)`). Start stays
    /// up a moment after the last Remove, until the sheet has gone (`settleFoot(after:)`), and
    /// does nothing then: the session starts nothing on a routine with no exercises.
    func pressStart() {
        guard phase == .idle, session.canStart(on: routine.id) else { return }
        // The list's end lies under the first row until it grows, so a short routine may have
        // nowhere to scroll it to: room under the end, out of sight, lets it go. It goes in
        // ahead of the scroll: a scroll in the same transaction stops at the old end.
        withTransaction(\.disablesAnimations, true) {
            // Held where it is: after an add's scroll to the list's end, the position stays
            // bound to that edge, and followed it down into the room, off the screen.
            scrollPosition.scrollTo(y: scrollBeat.scrolledY)
            isMakingRoom = true
            endFollow = nil
            startDrop = 0
            // Where a workout that ended left its current exercise: the first row reports its
            // own place from the press, and the landing's room waits for it.
            currentPlace = nil
        }
        phase.pressStart()
        let pressed = routine.id
        sequence.run {
            let start = ContinuousClock.now
            try await beat(until: start + .seconds(Self.pressHold))
            try await leave(pressed)
        }
    }

    /// Start in beats, each once the last has finished: if the first exercise is
    /// scrolled away, the list scrolls to its top and holds a moment; then the first
    /// exercise grows into the current one as the list scrolls it up under the bar, in one
    /// motion, and the key rides down off the screen with the rows below it. With Reduce
    /// Motion, the list crossfades into the workout.
    private func leave(_ pressed: Routine.ID) async throws {
        // What the first row gives back as it shrinks, which the move off it lands by.
        noteRestingPitch(of: routine.exercises.first?.id)
        guard !reduceMotion else {
            try check(pressed)
            beginCrossfade(scrollingTo: currentPlace?.landingY ?? scrollBeat.scrolledY)
            // The change on a later turn of the run loop, once the list going out has been drawn
            // lifted and cut: in the same update, it went out with neither.
            try await laterTurn()
            try check(pressed)
            try await crossfade {
                session.start(on: pressed)
                // The bar's room goes for the crossfade: the room under the list holds it, and
                // measured, the list stayed put (13 Starts, 2026-11-01).
                phase.fadeIn()
            }
            return keyReturns { phase.run() }
        }
        try await bringFirstIntoView()
        try check(pressed)
        grow(pressed)
        // The workout's key comes up as the rows land, a beat in the sequence by design: the
        // animation's completion came a few frames after the rows had stopped, and the key rose
        // after a pause. Start leaves the bar with its room kept: taken with it, the list's
        // bottom inset dropped 68 pt as the room under the list went, and the list sometimes
        // stayed about 60 pt low.
        try await beat(until: .now + .seconds(Self.keyReturnDelay))
        withTransaction(\.disablesAnimations, true) {
            phase.landStart()
            startDrop = 0
        }
        letRoomGo()
        // On a later turn of the run loop, once Start has gone: in the same update, away and
        // back cancel out, and the key jumped back up from its drop. Still before the bar's
        // reactions run, so the bar draws it back from what it already holds
        // (`KeyStage.dropped`).
        try await laterTurn()
        keyReturns { phase.run() }
    }

    /// If the first exercise is scrolled away, scrolls the list to its top, then gives the
    /// landing a beat to itself: a pause in the sequence, by design. At once if it is in view.
    /// A scroll that never reports stopping is given up after `scrollGiveUp`, and Start carries
    /// on: the grow scrolls at once from wherever the list is.
    private func bringFirstIntoView() async throws {
        guard currentPlace?.isScrolledAway == true else { return }
        if !scrollBeat.isListAtTop {
            await scrollBeat.settled {
                withAnimation(.snappy(duration: Self.scrollDuration)) {
                    scrollPosition.scrollTo(edge: .top)
                }
            } orWhen: {
                try? await Task.sleep(for: .seconds(Self.scrollGiveUp), tolerance: .zero)
            }
        }
        try await beat(until: .now + .seconds(Self.landingHold))
    }

    /// Stops Start's beats unless the session would still start a workout on `pressed`, the
    /// routine Start was pressed on: a switch of routine while they play, under way or done, stops
    /// them, so the grow never plays with no workout behind it. Called in the same turn as each
    /// `start(on:)`, which holds the same rule whoever calls it. The screen settles at rest as it
    /// stops: a switch that fails to read its routine leaves this screen showing.
    private func check(_ pressed: Routine.ID) throws {
        guard session.canStart(on: pressed) else {
            stopSequence()
            throw CancellationError()
        }
    }

    /// The first exercise grows into the current one as the list scrolls it up under the bar,
    /// one motion on one curve, the rows below stepping aside and Start riding down off the
    /// screen as they do. An animated scroll held the growth back until it had nearly landed, so
    /// the list is scrolled at once and drawn where it was, then both run in one animation.
    private func grow(_ pressed: Routine.ID) {
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
            session.start(on: pressed)
            phase.grow()
            growthLift = 0
            startDrop = max(drop, 1)
            // On the rows' own animation: until it has ended, a loop's heads ease to their new
            // places (`listResizes(_:)`).
            resizes += 1
        }
    }

    /// Where the list lands the current exercise while it is landing on it or resting on it:
    /// from Start's press, through the workout and through a move to the next exercise; after
    /// the last set, the room closing with its row. None out of a workout.
    ///
    /// On from Start's press, at its full height, before the grow's animated transaction: the
    /// scroll view's own content size follows the content's on that transaction's curve, behind
    /// it. Switched on with the grow, the room grew in with it, and when the room under the list
    /// went mid-grow the scroll view's trailing size, 45 to 130 pt short, clamped the list down.
    var landingRoomTop: CGFloat? {
        let isLanding = currentID != nil || isMovingOn || isStarting || isResting
        return closingRoomTop ?? (isLanding ? currentPlace?.landingY : nil)
    }

    /// Takes away the screen's room under the list's end once Start or a move to the next
    /// exercise is over. It can go at any moment: `landingRoomTop` holds the landing.
    func letRoomGo() {
        guard isMakingRoom, !isStarting, !isMovingOn, !isResting, session.workout != nil
        else { return }
        withTransaction(\.disablesAnimations, true) { isMakingRoom = false }
    }

    /// Ends the workout with `change`, Start's grow in reverse, in one motion: the current
    /// exercise shrinks back to a resting row as the rows below close up, and the list scrolls
    /// back to its top. Once that lands, Start comes up on its own from below the screen's edge,
    /// a short beat with no overshoot. The scroll is animated, not lifted
    /// as at Start: drawn lifted at the top, the title showed over the status bar, with no edge
    /// effect under the bar. On a curve that eases out and stops at its duration: a spring's
    /// settling tail made the end feel slow and heavy as it landed. With Reduce Motion, the list
    /// crossfades, then Start fades in.
    ///
    /// End takes over from whatever was playing: its beats stop, and nothing of it plays after.
    /// The pulse goes at once. What End moves, it moves from where it is drawn: a set logged and
    /// not yet drawn stays hidden (`WorkoutPhase.end(_:)`), and the lift is set to what is drawn,
    /// on a turn of their own, before the shrink: a new transaction leaves an animation still
    /// pending on a view alone where it doesn't change the view's value. A row already shifting
    /// finishes its shrink on the move's own curve. As Dave decided, having tried it
    /// (2026-11-14).
    ///
    /// `change`, the store's finish or discard, is made at once, here, on every path: only the
    /// motion is the sequence's, which the screen going away cancels. The list draws the workout
    /// as it was from the phase (`WorkoutPhase.drawnWorkout`) until it shrinks or crossfades out
    /// of it. `change` takes the curve the bar's End and time would have moved on with it.
    func end(_ change: () -> Void) {
        // Once only: a second End is refused.
        var ended = phase
        guard let workout = session.workout, ended.end(workout) else { return }
        sequence.cancel()
        let tookOver = phase != .running
        withTransaction(\.disablesAnimations, true) {
            // The next workout's key starts from the log, whatever this one's last showed.
            keyWayBack = nil
            phase = ended
            if tookOver {
                growthLift = shownLift.value
                railPulse = nil
            }
        }
        // The workout's key slides down as it fades, and Start stays away until the list has
        // landed: taken out with no animation, the key went on the frame.
        withAnimation(.easeOut(duration: Self.barFade)) { phase.keyLeaves() }
        guard !reduceMotion else {
            withAnimation(Self.crossfadeCurve) { change() }
            beginCrossfade(scrollingTo: 0)
            return sequence.run {
                let start = ContinuousClock.now
                try await laterTurn()
                try await crossfade {
                    phase.listLeaves()
                    // Any room Start or a move was keeping: there is no landing after End.
                    isMakingRoom = false
                    closingRoomTop = nil
                } meanwhile: {
                    try await beat(until: start + .seconds(Self.barFade))
                    fadeTime()
                }
                keyReturns { phase.rest() }
            }
        }
        if tookOver {
            withAnimation(Self.endCurve) { change() }
        } else {
            shrink(storing: change)
        }
        sequence.run {
            let start = ContinuousClock.now
            if tookOver {
                try await laterTurn()
                shrink()
            }
            // Once the time has faded out of its key, the key's glass goes, the bar fading it:
            // taken out with no animation, it went on the frame. A beat in the sequence by design.
            try await beat(until: start + .seconds(Self.barFade))
            fadeTime()
            // Start comes back as the list lands, a beat in the sequence by design: the
            // animation's completion came a few frames after the rows had stopped.
            try await beat(until: start + .seconds(Self.endBeat))
            if startDrop != 0 {
                // Ended as Start rode down: it comes back from out of sight.
                withTransaction(\.disablesAnimations, true) { startDrop = 0 }
                try await laterTurn()
            }
            keyReturns { phase.rest() }
        }
    }

    /// End's one motion, with `change` when End took over nothing: the list leaving the workout,
    /// the current exercise shrinking, the rows
    /// below closing up, and the list scrolling to its top, on the rows' own animation: until it
    /// has ended, room under the list's end holds, so the shrinking content doesn't pull the
    /// scroll up, and a loop's heads ease to their new places, as at Start (`listResizes(_:)`).
    private func shrink(storing change: () -> Void = { }) {
        withAnimation(Self.endCurve) {
            change()
            phase.listLeaves()
            scrollPosition.scrollTo(edge: .top)
            resizes += 1
            // Any room a move to the next exercise or the last set's close left: the resize
            // holds the room from here.
            isMakingRoom = false
            closingRoomTop = nil
            growthLift = 0
        }
    }

    /// A key comes back up into the bar, the workout's after Start, Start after End, with `step`,
    /// the phase's last transition.
    private func keyReturns(_ step: () -> Bool) {
        withAnimation(.smooth(duration: Self.startReturn)) { _ = step() }
    }

    /// The time fades out of its key as the workout ends, and then the key's glass goes.
    private func fadeTime() {
        withAnimation(.easeOut(duration: Self.barFade)) { _ = phase.timeFades() }
    }

    /// With Reduce Motion, one crossfade, for Start, a move, and End: the list as it was fades
    /// out where it shows while the list changed fades in over it, scrolled to `y`, as Start
    /// fades out if it goes. The changed list is a new view, so the old one stays on screen as
    /// it fades: faded out first and in after, the screen showed empty between. The old one is
    /// drawn lifted by as far as the scroll jumps, so it holds still, with what was under the
    /// bar cut away (`TopClip`): scrolled to the top, the bar has no edge effect, and it showed
    /// through. This is its first half, in the caller's turn: the list going out drawn lifted and
    /// cut, where it shows, the list scrolled to `y` under it; the change follows on a later turn
    /// of the run loop (`crossfade(_:meanwhile:)`): in the same update, the list went out with
    /// neither.
    func beginCrossfade(scrollingTo y: CGFloat) {
        let from = scrollBeat.scrolledY
        withTransaction(\.disablesAnimations, true) {
            isCrossfading = true
            growthLift = y - from
            underBarCut = max(from - y, 0)
            scrollPosition.scrollTo(y: y)
        }
    }

    /// The crossfade itself, on a later turn than `beginCrossfade(scrollingTo:)`: the changed
    /// list fading in over the one going out, with `meanwhile` playing as it fades. Returns once
    /// the fade has finished, as its animation's completion reports; throws if the sequence
    /// awaiting it was cancelled, and then clears nothing.
    func crossfade(
        _ change: () -> Void,
        meanwhile: () async throws -> Void = { },
    ) async throws {
        let (finished, finish) = AsyncStream<Void>.makeStream()
        withAnimation(Self.crossfadeCurve) {
            listChanges += 1
            growthLift = 0
            underBarCut = 0
            change()
        } completion: {
            finish.finish()
        }
        try await meanwhile()
        // Ends as the fade finishes, or at once if the sequence is cancelled.
        for await _ in finished { }
        try Task.checkCancellation()
        withTransaction(\.disablesAnimations, true) { isCrossfading = false }
        letRoomGo()
    }

    /// Notes where the first exercise is, which a relaunch waits for. In a workout, where the
    /// list was landed on it and what is above it changes height, as after a text size change
    /// or a rename to a longer name, the list lands on it again: the title's text view settles
    /// its height a pass after the rest, so one landing as the change came in fell short. A
    /// landing counts once asked for (`ScrollBeat.rests(on:asked:)`): after Start on a pushed
    /// routine, the fresh root screen's row rises into place, and one landing was reported late.
    func placeCurrent(_ place: CurrentPlace) {
        let old = currentPlace
        currentPlace = place
        letRoomGo()
        // Not while moving to the next exercise, which lands it: its place, read as it grows,
        // is on the way there.
        if let old, currentID != nil, !isScrollingByHand, !isMovingOn,
           place.contentTop != old.contentTop,
           scrollBeat.rests(on: old.landingY, asked: scrollPosition)
        {
            scrollToCurrent()
        }
        openOnCurrentIfDue()
        settleWayBack()
    }

    /// Back in a workout after a relaunch, opens the list on the current exercise, once it has
    /// its place in a list with a height. Wherever the row is: at the largest text sizes, the
    /// equipment under the title can leave it below the screen.
    func openOnCurrentIfDue() {
        guard opensOnCurrent, currentPlace?.isLaidOut == true else { return }
        opensOnCurrent = false
        scrollToCurrent()
        settleWayBack()
    }

    /// The beat between Start's press and its leaving. The workout's first frame takes a few
    /// more to draw, so the rows move about 0.5 s after the press.
    static let pressHold = 0.4
    static let scrollDuration = 0.35
    /// How long Start waits for its scroll to the first exercise to report it has stopped
    /// before it carries on: about twice the longest measured, from the end of a ten-exercise
    /// routine, 0.58 to 0.62 s from the scroll's start (2026-11-14). No scroll was seen that
    /// never reported stopping; this bounds the wait if one does. Carrying on, not waiting, is
    /// Dave's call (2026-11-14).
    static let scrollGiveUp = 1.25
    /// The first exercise growing at Start, the rows below stepping aside.
    static let growBeat = 0.55
    /// From the grow's start until the workout's key starts up, as the rows visibly land: the
    /// snappy curve's last 0.1 s moves them under a point.
    static let keyReturnDelay = 0.45
    /// The current exercise shrinking back at the end, the rows below closing up, on a curve
    /// quick off the mark that eases gently into place and stops at its duration, with no
    /// spring's tail.
    static let endBeat = 0.4
    static let endCurve = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: endBeat)
    /// The bar's keys fading at a workout's end: End for ++, and the time out of its key, then
    /// the key's glass.
    static let barFade = 0.2
    /// The key coming back once Start's grow or the end's shrink has landed.
    static let startReturn = PrimaryKeyButtonStyle.swapHalf
    /// With Reduce Motion, the list crossfading into a workout or out of one.
    static let crossfadeDuration = 0.35
    static let crossfadeCurve = Animation.easeInOut(duration: crossfadeDuration)
    /// The pause between Start's scroll to the top landing and the row growing.
    static let landingHold = 0.2
}

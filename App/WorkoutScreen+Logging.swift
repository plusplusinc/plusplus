import DesignSystem
import SwiftUI
import WorkoutStore

/// A workout's sets as the screen draws them, and `play(_:leadingTo:)`, which shows what a
/// stored log leads to: the next set, the move to the next exercise, or the close after the last.
extension WorkoutScreen {
    /// The workout in progress as stored, every log in it: what the key's taps read.
    var live: LiveWorkout? {
        session.loggedWorkout.map { LiveWorkout(workout: workout, loggedWorkout: $0) }
    }

    /// The workout as the screen draws it: `live`, or as End took it from the store until the
    /// list leaves it (`WorkoutPhase.drawnLoggedWorkout`), less the sets logged and not yet shown
    /// (`WorkoutPhase.hidden`). Everything drawn reads it.
    var shown: LiveWorkout? {
        let loggedWorkout = session.loggedWorkout ?? phase.drawnLoggedWorkout
        return loggedWorkout
            .map { LiveWorkout(workout: workout, loggedWorkout: $0).hiding(phase.hidden) }
    }

    /// While a step to another exercise, or past the last set, plays: rows' heights are
    /// mid-motion, and the key logs nothing.
    var isMovingOn: Bool {
        phase.isMovingOn
    }

    /// The exercise the workout is on, as drawn. None once every set is logged.
    var currentID: WorkoutExercise.ID? {
        // Resting between exercises, no row is grown once the rest shows: the next grows as the
        // rest ends. Until then the row left stays grown, so it shrinks in the rest's animated
        // transaction, not at the log's: changed at the log, it went at once and the rows below
        // jumped up before the rest opened and pushed them back down.
        // Between two sets of one exercise, it stays grown.
        phase.drawnRest.map { $0.isWithinExercise || $0.beat == .logged } ?? true
            ? shown?.currentSet?.row : nil
    }

    /// The row whose node is lit on the rail: the current exercise, but while a move to it is on
    /// its way, none until the pulse lands on its node, nor through a rest, whose dot is the
    /// green on the rail.
    var litID: WorkoutExercise.ID? {
        phase.move.map(\.isLanded) == false
            || phase.drawnRest.map { !$0.isWithinExercise } == true
            ? nil : currentID
    }

    /// A set logged that stays on the current exercise, saved at once, but shown as still to do
    /// for a beat after the key's tap (`SetMotion.heldRoll`), when the line rolls on
    /// (`WorkoutPhase.held`).
    var heldSet: PlannedSet? {
        phase.held
    }

    /// Which way the move to another exercise under way goes along the rail, which sets the
    /// pulse's travel and when the shift starts.
    var moveWay: SetMotion.Way? {
        // Into a rest between exercises, the rows change from the tap, with no landing to wait
        // for (`SetMotion.aroundRest(_:)`), so the parts go at once, as after the last set.
        if phase.resting != nil {
            return nil
        }
        // Out of a rest, the next exercise opens as the dot leaves, its parts coming in as at
        // Start, with no landing to wait for (`SetMotion.aroundRest(_:)`).
        guard let move = phase.move, !move.isFromRest else { return nil }
        return move.way
    }

    /// The current exercise as it grows into `set`, `after` at its caption line's end:
    /// at a superset round's end, it shows the round just done, as the logged set's row showed
    /// it, until the move rolls it to the new one.
    func focus(of item: WorkoutExercise, on set: PlannedSet, after: CaptionEnd?) -> RowFocus {
        var focus = item.focus(on: set, inSuperset: workout.isInSuperset(item.id), locale: locale)
        focus.after = after?.text
        focus.spokenAfter = after?.spoken
        if let move = phase.move, move.holdsRound,
           let left = workout.exercises.first(where: { $0.id == move.set.row })
        {
            focus.place = left.place(
                set: move.set.round,
                inSuperset: workout.isInSuperset(left.id),
                locale: locale,
            )
        }
        // On a set's first side the other side follows, so nothing is said at the line's end, but
        // the second side's words keep their room there: the line stacked on the second side
        // alone, and the equipment below jumped down a line between the two. With this side
        // logged: else the other led back to it, and a superset's member promised no rest.
        if let side = set.side, let last = Side.allCases.last, side != last, let shown {
            focus.after = afterText(
                for: PlannedSet(row: set.row, round: set.round, side: last),
                in: shown,
                after: [set],
            )?.text
            focus.showsAfter = false
        }
        timedCaption(&focus, of: item)
        // Resting between two sets, the line says the set just done, "Set 1 of 3 done", until
        // the next set's number rolls in as "done" goes; the caption line's end still says the
        // rest it went to as it fades, not what follows the next set.
        if let rest = phase.drawnRest, rest.isWithinExercise, rest.beat >= .shown,
           rest.beat < .returning, rest.set.row == item.id
        {
            focus.place.number = rest.set.round
            // Done one side at a time, the set just done was both sides: "done" takes the side's
            // place (`RowFocus.showsSide`). The next set's side waits there unseen, so the rest's
            // end only fades it back in, never fading it over "done".
            focus.place.isDone = true
            focus.after = drawnResting.map { thenRest($0.rest.length).text }
        }
        return focus
    }

    /// A row's label: the current exercise, grown, on `set`; else a row, with its parts. Given
    /// the screen's values read once, as the rows' closure holds them: read here, a list
    /// crossfading out took the bars of the workout it faded into, a finished row's gone at once.
    func rowLabel(
        _ item: WorkoutExercise,
        current: WorkoutExercise.ID?,
        on set: PlannedSet?,
        parts: RowParts?,
    ) -> RowLabel {
        let focus = item.id == current
            ? set.map { focus(of: item, on: $0, after: parts?.after) } : nil
        return RowLabel(
            title: item.exercise.name,
            detail: item.detailParts(locale: locale),
            spokenDetail: item.spokenDetail(locale: locale),
            focus: focus,
            bars: parts?.bars,
            setRest: parts?.restBetween,
            isDone: parts?.isDone ?? false,
            nextUp: parts?.nextUp,
        )
    }

    /// The set bars each row shows in `shown` (`LiveWorkout.bars(of:)`), for the rows' closure
    /// to hold as values.
    func rowBars(in shown: LiveWorkout?) -> [WorkoutExercise.ID: SetProgress] {
        guard let shown else { return [:] }
        let restingTo = phase.drawnRest.flatMap { $0.beat > .logged ? shown.currentSet?.row : nil }
        return workout.exercises.reduce(into: [:]) { bars, item in
            guard let (done, total) = shown.bars(of: item.id),
                  // Resting, the next exercise is a row like any other until it grows.
                  item.id != restingTo || done > 0
            else { return }
            bars[item.id] = SetProgress(
                done: done,
                total: total,
                spoken: spokenProgress(done: done, total: total, locale: locale),
            )
        }
    }

    /// The row that grows, or stands grown: the current exercise, or, out of a workout, the
    /// first, which Start grows.
    var growingID: WorkoutExercise.ID? {
        guard shown != nil else { return workout.exercises.first?.id }
        // Relaunched into a rest between exercises, no row is grown until it ends: the list opens
        // on the row the rest is drawn in.
        return currentID ?? (opensOnCurrent ? restDotRow : nil)
    }

    /// Plays `step`, what logging `set` led to, the set already stored: the screen's one entry
    /// for showing a log. It enters the screen's phase (`WorkoutPhase`), which draws the workout
    /// without the set until its motion shows it.
    ///
    /// Within one exercise the set is held from showing (`heldSet`), the current node small and
    /// gray, for `SetMotion.heldRoll`, when the progress line and the bars roll on
    /// (`rollHeldSet()`). Moving to another, one motion from the log (`SetMotion`): the parts
    /// under the current exercise's name go, bottom first, and on one curve its row shrinks back
    /// to a resting row as the next row grows into the current exercise and the list scrolls it
    /// up under the bar, so the rows below move up once, with the scroll. The node left is pulled
    /// out first into a blob of green that runs along the rail to the next node and plops into
    /// it, with a light tick, the node lighting as it settles (`PulseShape`), on a still screen:
    /// down the rail and round a superset's loop alike, the current exercise's parts go and the
    /// shift starts only `SetMotion.landingHold` after the landing. The scroll is Start's: the
    /// list is scrolled at once to where the next row will land and drawn where it was, the lift
    /// run to 0 in the shift's transaction. After the last set, the row closes as the list
    /// settles on its end and the key becomes Finish workout.
    func play(_ set: PlannedSet, leadingTo step: LiveWorkout.Step) {
        // In the tap's own transaction, as the stored log is: entered with animations disabled,
        // the last set's room went at once, the list jumping to its top.
        // Only from rest: the key takes a log only then, so a refused one has nothing to show.
        guard phase.log(
            set,
            leadingTo: step,
            rests: live?.rests(after: set, leadingTo: step, override: restOverride) ?? false,
            moves: !reduceMotion,
        )
        else { return }
        if phase.resting != nil {
            return startRest()
        }
        let next: PlannedSet?
        let isBack: Bool
        switch step {
        case .nextSet:
            return rollHeldSet()
        case let .nextExercise(to, back, _):
            (next, isBack) = (to, back)
        case .last:
            (next, isBack) = (nil, false)
        }
        let target = next.flatMap { landing(on: $0.row, leaving: set.row) }
        guard !reduceMotion else {
            return crossfadeOn(to: next, scrollingTo: target)
        }
        guard let next else { return closeLast() }
        let way = SetMotion.Way(isBack: isBack)
        // The node left goes to its own color at once, under the pulse pulling out of it, which
        // leaves it behind in that color as its neck snaps. At a superset round's end, the next
        // row shows the round just done until it rolls on (`focus(of:on:)`).
        withTransaction(\.disablesAnimations, true) {
            if let target {
                isMakingRoom = true
                // A row still entering stays where it is, as at Start (`pressStart()`).
                endFollow = nil
                liftScroll(to: target)
            }
        }
        // One transaction: the parts going and coming each on their own delays
        // (`part(_:)`), both rows' heights, their names, and the lift on the shift's curve.
        withAnimation(SetMotion.moving(way)) {
            phase.show()
            growthLift = 0
        }
        railPulse = RailPulse(
            from: .node(set.row),
            to: .node(next.row),
            way: way,
            run: (railPulse?.run ?? 0) + 1,
        )
        land(way, scrollingTo: target)
    }

    /// With Reduce Motion, moving on, or closing after the last set, is one crossfade, the tick
    /// played as the next node lights in it. A move like any other: the current exercise's place
    /// changing under it doesn't land it again (`placeCurrent(_:)`), and the key logs nothing
    /// until it is over. With no `target` worked out ahead, the list lands after. `endingRest`: the
    /// rest between exercises ends inside the fade, its set drawn as it
    /// was, so the rest is what fades out.
    func crossfadeOn(to next: PlannedSet?, scrollingTo target: CGFloat?, endingRest: Bool = false) {
        beginCrossfade(scrollingTo: target ?? scrollBeat.scrolledY)
        sequence.run {
            try await crossfade {
                _ = endingRest ? phase.endRest(moves: false) : phase.show()
                if next != nil {
                    landings += 1
                }
            }
            phase.settle(on: arrivingCount())
            letRoomGo()
            if next != nil, target == nil {
                scrollToCurrent()
            }
            settleWayBack()
        }
    }

    /// A move's landing, with its tick and the node lighting under the pulse's plop, the shift's
    /// start, which End reads, the round's roll once the next row shows it, then the move's end,
    /// timed from the log by design: nothing is waited for. With no `target` worked out ahead, the
    /// list lands after, in a second motion.
    func land(_ way: SetMotion.Way, scrollingTo target: CGFloat?) {
        sequence.run {
            let start = ContinuousClock.now
            try await beat(until: start + .seconds(SetMotion.landing(way)))
            landings += 1
            // At once, under the plop, which is the lit node's size and green.
            withTransaction(\.disablesAnimations, true) {
                phase.land()
            }
            // Nothing drawn reads it: from here, End lets the row left finish its shrink.
            try await beat(until: start + .seconds(SetMotion.moveShiftStart(way)))
            withTransaction(\.disablesAnimations, true) {
                phase.shift()
            }
            try await beat(until: start + .seconds(SetMotion.roundRoll(way)))
            withAnimation(.snappy(duration: SetMotion.roll)) {
                phase.roll()
            }
            try await beat(until: start + .seconds(SetMotion.move(way)))
            phase.settle(on: arrivingCount())
            // At once, the figure carried from a rest standing where the slot's own does.
            withTransaction(\.disablesAnimations, true) { figureCarry = nil }
            letRoomGo()
            if target == nil {
                withAnimation(.snappy(duration: SetMotion.roll), scrollToCurrent)
            }
            settleWayBack()
        }
    }

    /// The workout's last planned set: the parts go, and the row closes back as the list
    /// settles on its end, in one motion, the key swapping to Finish workout once it is over. The
    /// room under the end that landed the row under the bar closes on the same curve, and the
    /// list's end stays where it shows as the content shortens, so what is above it moves down,
    /// once, and never back.
    private func closeLast() {
        withTransaction(\.disablesAnimations, true) {
            closingRoomTop = currentPlace?.landingY ?? scrollBeat.scrolledY
        }
        withAnimation(SetMotion.closing) {
            phase.show()
            closingRoomTop = 0
        }
        sequence.run {
            let start = ContinuousClock.now
            try await beat(until: start + .seconds(SetMotion.closeStart + SetMotion.close))
            closingRoomTop = nil
            phase.settle(on: arrivingCount())
            letRoomGo()
            settleWayBack()
        }
    }

    /// After the last set, while the room under the list's end closes, keeps the end where it
    /// shows as the content shortens, a frame at a time, as `keepEndInView(from:to:)` does as it
    /// grows.
    func keepEndPinned(from old: ScrollExtent, to new: ScrollExtent) {
        guard closingRoomTop != nil, new.contentHeight < old.contentHeight else { return }
        let shrink = old.contentHeight - new.contentHeight
        withTransaction(\.disablesAnimations, true) {
            scrollPosition.scrollTo(y: max(new.scrolledY - shrink, 0))
        }
    }

    /// Finishes the workout from the key, at once, with no dialog, as End's Finish does.
    func finish() {
        end { session.finish() }
    }

    /// Where the list lands `next`'s row under the bar once `leaving`, the current row, has
    /// shrunk back: at the row's top, where its label lands just under the bar. A row above
    /// stays where it is; one below rises by what `leaving` gives back, from its pitch now, top
    /// to the next row's top, to its pitch at rest, measured from a copy of it at rest while it
    /// was current (`notesRestingPitch(of:current:)`). Nil when either isn't known.
    func landing(on next: WorkoutExercise.ID, leaving: WorkoutExercise.ID) -> CGFloat? {
        guard let nextTop = rowFrames.tops[next], let leavingTop = rowFrames.tops[leaving]
        else { return nil }
        guard nextTop > leavingTop else { return max(nextTop, 0) }
        guard let after = workout.neighbor(of: leaving, .below).flatMap({ rowFrames.tops[$0.id] }),
              let resting = rowFrames.restingPitch[leaving]
        else { return nil }
        return max(nextTop - (after - leavingTop - resting), 0)
    }

    /// Where the list lands `next`'s row under the bar as a rest between exercises ends: up by the
    /// rest closing under the row left, already a resting row, all it gives back. Nil when the
    /// row isn't known.
    func landing(
        on next: WorkoutExercise.ID,
        closingRestUnder leaving: WorkoutExercise.ID,
    ) -> CGFloat? {
        guard let nextTop = rowFrames.tops[next] else { return nil }
        return max(nextTop - (rowFrames.restHeights[leaving] ?? 0), 0)
    }

    /// Whether the key shows, Start or the workout's: with exercises, and not gone for Start's
    /// grow or a workout's end (`WorkoutPhase.keyGone`), and not while the set waits on its
    /// "Start in" or its 0:00 hold, where its room stays (`keyKeepsRoom`) and the set's key comes
    /// in as the set is up (decided 2026-11-24).
    var showsKey: Bool {
        !footShowsEmpty && phase.keyGone == nil && !liveKey.waitsToStart
    }

    /// Whether the bar keeps the key's room with no key in it, so nothing above moves.
    var keyKeepsRoom: Bool {
        phase.keyGone == .keepingRoom || liveKey.waitsToStart
    }
}

extension SetMotion.Way {
    /// The way along the rail to a row above the one left (`isBack`), round a loop, or below.
    init(isBack: Bool) {
        self = isBack ? .loop : .down
    }
}

extension WorkoutPhase.Move {
    /// Which way the move goes along the rail.
    var way: SetMotion.Way {
        SetMotion.Way(isBack: isBack)
    }
}

/// Where each row is in the list's content, and each row's height when last at rest, read as
/// a move begins. Not observed: rows report as they lay out, and redrawing the screen for each
/// would redraw it on every frame of a move.
final class RowFrames {
    var tops: [WorkoutExercise.ID: CGFloat] = [:]
    /// Each row's pitch at rest, top to the next row's top, as it will rest once a set has moved
    /// the workout off it: what it gives back as it shrinks.
    var restingPitch: [WorkoutExercise.ID: CGFloat] = [:]
    /// The height of the rest under each row, open or not.
    var restHeights: [WorkoutExercise.ID: CGFloat] = [:]
}

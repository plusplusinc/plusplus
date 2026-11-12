import DesignSystem
import SwiftUI
import WorkoutStore

/// A workout's sets as the screen draws them, and `play(_:)`, which shows what a stored log leads
/// to: the next set, the move to the next exercise, or the close after the last.
extension RoutineScreen {
    /// The workout on the routine as stored, every log in it: what the key's taps read.
    var live: LiveWorkout? {
        session.workout.map { LiveWorkout(routine: routine, workout: $0) }
    }

    /// The workout as the screen draws it: `live` less the sets logged and not yet shown
    /// (`WorkoutPlayback.unshown`). Everything drawn reads it.
    var shown: LiveWorkout? {
        live?.hiding(playback.unshown)
    }

    /// While a step to another exercise, or past the last set, plays: rows' heights are
    /// mid-motion, and the key logs nothing.
    var isMovingOn: Bool {
        playback.isMovingOn
    }

    /// The exercise the workout is on, as drawn. None once every set is logged.
    var currentID: RoutineExercise.ID? {
        shown?.currentSet?.row
    }

    /// The row whose node is lit on the rail: the current exercise, but while a move to it is on
    /// its way, none until the pulse lands on its node.
    var litID: RoutineExercise.ID? {
        exerciseMove.map { $0.isLanded } == false ? nil : currentID
    }

    /// A set logged that stays on the current exercise, saved at once, but shown as still to do
    /// for a beat after the key's tap (`SetMotion.heldRoll`), when the line rolls on.
    /// None once another set is logged, as in another workout.
    var heldSet: PlannedSet? {
        guard let held = playback.held, session.workout?.sets.last?.planned == held else {
            return nil
        }
        return held
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

    /// A row's label: the current exercise, grown, on `set`; else a row, with its `bars`. Given
    /// the screen's values read once, as the rows' closure holds them: read here, a list
    /// crossfading out took the bars of the workout it faded into, a finished row's gone at once.
    func rowLabel(
        _ item: RoutineExercise,
        current: RoutineExercise.ID?,
        on set: PlannedSet?,
        bars: SetProgress?,
    ) -> RowLabel {
        let focus = item.id == current ? set.map { focus(of: item, on: $0) } : nil
        return RowLabel(
            title: item.exercise.name,
            detail: item.detailParts(locale: locale),
            spokenDetail: item.spokenDetail(locale: locale),
            focus: focus,
            bars: bars,
        )
    }

    /// Each row's bars (`bars(of:)`), for the rows' closure to hold as values.
    var rowBars: [RoutineExercise.ID: SetProgress] {
        routine.exercises.reduce(into: [:]) { bars, item in bars[item.id] = self.bars(of: item.id) }
    }

    /// The set bars a row shows in a workout (`LiveWorkout.bars(of:)`), as drawn.
    func bars(of id: RoutineExercise.ID) -> SetProgress? {
        guard let (done, total) = shown?.bars(of: id) else { return nil }
        return SetProgress(
            done: done,
            total: total,
            spoken: spokenProgress(done: done, total: total, locale: locale),
        )
    }

    /// The row that grows, or stands grown: the current exercise, or, out of a workout, the
    /// first, which Start grows.
    var growingID: RoutineExercise.ID? {
        session.workout == nil ? routine.exercises.first?.id : currentID
    }

    /// Plays the step that logging `set` leads to, the set already stored: the screen's one
    /// entry for showing a log, whoever made it. The step is judged from the workout as drawn
    /// then (`shown`), so a set that waited its turn is judged against what the screen has.
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
    func play(_ set: PlannedSet) {
        let step = shown?.step(logging: set) ?? .nextSet
        playback.start(step, for: set)
        guard let row = routine.exercises.first(where: { $0.id == set.row }) else {
            // Its row is gone: nothing to show it on.
            playback.show()
            return endStep()
        }
        let next: PlannedSet?
        let isBack: Bool
        let startsRound: Bool
        switch step {
        case .nextSet:
            // `rollHeldSet()` shows it, keyed on the held set.
            return
        case let .nextExercise(to, back, round):
            (next, isBack, startsRound) = (to, back, round)
        case .last:
            (next, isBack, startsRound) = (nil, false, false)
        }
        let target = next.flatMap { landing(on: $0.row, leaving: row.id) }
        noteRestingPitch(of: next?.row)
        // The key keeps the words it had until the next row shows its set, so it changes with
        // the row: read live, it said the next exercise's set ("Log left") as the pulse set off.
        heldKeyRole = keyRole
        guard !reduceMotion else {
            return crossfadeOn(to: next, scrollingTo: target)
        }
        guard let next else { return closeLast() }
        // At a superset round's end, the round just done rolls to the next once the first member
        // has grown to show it.
        let held = startsRound ? focus(of: row, on: set).progress : nil
        let way: SetMotion.Way = isBack ? .loop : .down
        // The node left goes to its own color at once, under the pulse pulling out of it, which
        // leaves it behind in that color as its neck snaps.
        withTransaction(\.disablesAnimations, true) {
            exerciseMove = ExerciseMove(way: way, heldProgress: held)
            if let target {
                isMakingRoom = true
                growthLift = target - scrollBeat.scrolledY
                scrollPosition.scrollTo(y: target)
            }
        }
        // One transaction: the parts going and coming each on their own delays
        // (`part(_:)`), both rows' heights, their names, and the lift on the shift's curve.
        withAnimation(SetMotion.moving(way)) {
            playback.show()
            growthLift = 0
        }
        railPulse = RailPulse(
            from: row.id,
            to: next.row,
            way: way,
            run: (railPulse?.run ?? 0) + 1,
        )
        land(way, scrollingTo: target)
    }

    /// The step playing is over: plays the set that waited longest, if one did.
    private func endStep() {
        if let waiting = playback.end() {
            play(waiting)
        }
    }

    /// With Reduce Motion, moving on, or closing after the last set, is one crossfade, the tick
    /// played as the next node lights in it. A move like any other: the current exercise's place
    /// changing under it doesn't land it again (`placeCurrent(_:)`), and the key logs nothing
    /// until it is over. With no `target` worked out ahead, as after a relaunch, the list lands
    /// after.
    private func crossfadeOn(to next: PlannedSet?, scrollingTo target: CGFloat?) {
        let landed = {
            var waiting: PlannedSet?
            swapKey { waiting = playback.end() }
            letRoomGo()
            if next != nil, target == nil {
                scrollToCurrent()
            }
            settleKeyRole()
            if let waiting {
                play(waiting)
            }
        }
        crossfade(scrollingTo: target ?? scrollBeat.scrolledY, then: landed) {
            playback.show()
            if next != nil {
                landings += 1
            }
        }
    }

    /// A move's landing, with its tick and the node lighting under the pulse's plop, the round's
    /// roll once the next row shows it, then the move's end, timed from the log by design: nothing
    /// is waited for. With no `target` worked out ahead, as after a relaunch, the list lands after.
    private func land(_ way: SetMotion.Way, scrollingTo target: CGFloat?) {
        Task {
            try? await Task.sleep(for: .seconds(SetMotion.landing(way)), tolerance: .zero)
            landings += 1
            // At once, under the plop, which is the lit node's size and green.
            withTransaction(\.disablesAnimations, true) {
                exerciseMove?.isLanded = true
            }
            try? await Task.sleep(
                for: .seconds(SetMotion.roundRoll(way) - SetMotion.landing(way)),
                tolerance: .zero,
            )
            withAnimation(.snappy(duration: SetMotion.roll)) {
                exerciseMove?.heldProgress = nil
                heldKeyRole = nil
            }
            try? await Task.sleep(
                for: .seconds(SetMotion.move(way) - SetMotion.roundRoll(way)),
                tolerance: .zero,
            )
            exerciseMove = nil
            let waiting = playback.end()
            letRoomGo()
            if target == nil {
                withAnimation(.snappy(duration: SetMotion.roll), scrollToCurrent)
            }
            settleKeyRole()
            if let waiting {
                play(waiting)
            }
        }
    }

    /// The workout's last planned set: the parts go, and the row closes back as the list settles
    /// on its end, in one motion, the key swapping to Finish workout once it is over. The room
    /// under the end that landed the row under the bar closes on the same curve,
    /// and the list's end stays where it shows as the content shortens, so what is above it moves
    /// down, once, and never back.
    private func closeLast() {
        withTransaction(\.disablesAnimations, true) {
            closingRoomTop = currentPlace?.landingY ?? scrollBeat.scrolledY
        }
        withAnimation(SetMotion.closing) {
            playback.show()
            closingRoomTop = 0
        }
        Task {
            try? await Task.sleep(
                for: .seconds(SetMotion.closeStart + SetMotion.close),
                tolerance: .zero,
            )
            closingRoomTop = nil
            var waiting: PlannedSet?
            swapKey { waiting = playback.end() }
            letRoomGo()
            settleKeyRole()
            if let waiting {
                play(waiting)
            }
        }
    }

    /// After the last set, while the room under the list's end closes, keeps the end where it
    /// shows as the content shortens, a frame at a time, as `keepEndInView(from:to:)` does as it
    /// grows.
    func keepEndPinned(from old: ScrollGeometry, to new: ScrollGeometry) {
        guard closingRoomTop != nil, new.contentSize.height < old.contentSize.height else { return }
        let shrink = old.contentSize.height - new.contentSize.height
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
    /// to the next row's top, to its pitch at rest, noted as it grew. Nil when either isn't
    /// known, as after a relaunch into a workout.
    private func landing(on next: RoutineExercise.ID, leaving: RoutineExercise.ID) -> CGFloat? {
        guard let nextTop = rowFrames.tops[next], let leavingTop = rowFrames.tops[leaving]
        else { return nil }
        guard nextTop > leavingTop else { return max(nextTop, 0) }
        guard let after = routine.neighbor(of: leaving, .below).flatMap({ rowFrames.tops[$0.id] }),
              let resting = rowFrames.restingPitch[leaving]
        else { return nil }
        return max(nextTop - (after - leavingTop - resting), 0)
    }

    /// Notes `id`'s pitch at rest, top to the next row's top, before it grows: what it gives
    /// back as it shrinks. The rail keeps a resting row to a rhythm, so it is more than its height.
    func noteRestingPitch(of id: RoutineExercise.ID?) {
        guard let id, let top = rowFrames.tops[id],
              let after = routine.neighbor(of: id, .below).flatMap({ rowFrames.tops[$0.id] })
        else { return }
        rowFrames.restingPitch[id] = after - top
    }

    /// Whether the key shows, Start or the workout's: with exercises, and not away for Start's
    /// grow or a workout's end.
    var showsKey: Bool {
        !routine.exercises.isEmpty && keyAway == nil
    }
}

/// A move from one exercise to the next in progress, from the log until the next has grown and
/// its parts have come in (`SetMotion`).
struct ExerciseMove {
    /// Which way it goes along the rail, which sets the pulse's travel and when the shift starts.
    var way: SetMotion.Way
    /// At a superset round's end, the round just done, which the first member shows as it grows,
    /// then rolls to its own (`SetMotion.roundRoll(_:)`).
    var heldProgress: String?
    /// Whether the pulse has landed on the next row's node, which then lights.
    var isLanded = false
}

/// Where each row is in the list's content, and each row's height when last at rest, read as
/// a move begins. Not observed: rows report as they lay out, and redrawing the screen for each
/// would redraw it on every frame of a move.
final class RowFrames {
    var tops: [RoutineExercise.ID: CGFloat] = [:]
    var restingPitch: [RoutineExercise.ID: CGFloat] = [:]
}

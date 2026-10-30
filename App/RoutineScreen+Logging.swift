import DesignSystem
import SwiftUI
import WorkoutStore

/// A workout's sets: the current exercise and its set, a log, and the move on to the next.
extension RoutineScreen {
    /// The exercise a workout is on: the row of the set it does next. None once every set is
    /// logged.
    var currentExercise: RoutineExercise? {
        currentSet.flatMap { set in routine.exercises.first { $0.id == set.row } }
    }

    var currentID: RoutineExercise.ID? {
        currentExercise?.id
    }

    /// The set a workout does next, the first in the routine's order not yet logged.
    var currentSet: PlannedSet? {
        session.workout.flatMap { routine.nextSet(after: $0.sets) }
    }

    /// The row whose node is lit on the rail: the current exercise, but while a move to it is on
    /// its way, none until the pulse lands on its node.
    var litID: RoutineExercise.ID? {
        exerciseMove.map { $0.isLanded } == false ? nil : currentID
    }

    /// Whether every planned set of the workout is logged, so the Finish row ends the list.
    var isWorkoutDone: Bool {
        session.workout != nil && !routine.exercises.isEmpty && currentSet == nil
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

    /// A row's label: the current exercise, grown, on `set`; else a row. Given the screen's
    /// values read once, as the rows' closure holds them.
    func rowLabel(
        _ item: RoutineExercise,
        current: RoutineExercise.ID?,
        on set: PlannedSet?,
    ) -> RowLabel {
        let focus = item.id == current ? set.map { focus(of: item, on: $0) } : nil
        return RowLabel(
            title: item.exercise.name,
            detail: item.detailParts(locale: locale),
            spokenDetail: item.spokenDetail(locale: locale),
            focus: focus,
            bars: bars(of: item.id),
            log: focus == nil ? nil : set.map { logStep($0, of: item) },
        )
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

    /// Logs the set the slide was on, at the numbers its row shows. Within one exercise the
    /// progress line rolls to the next set. Moving to another, one motion from the log
    /// (`SetMotion`): the parts under the current exercise's name go, bottom first, and on one
    /// curve its row shrinks back to a resting row as the next row grows into the current
    /// exercise and the list scrolls it up under the bar, so the rows below move up once, with
    /// the scroll. The node left is pulled out first into a blob of green that runs along the
    /// rail to the next node and plops into it, with a light tick, the node lighting as it
    /// settles (`PulseShape`): down the rail, the current exercise holds until just before the
    /// landing, when its parts go and the shift starts; round a superset's loop at a round's end,
    /// the shift follows the pulse as if tethered, settling just after it lands. The scroll is
    /// Start's:
    /// the list is scrolled at once to where the next row will land and drawn where it was, the
    /// lift run to 0 in the shift's transaction. After the last set, the row closes as the list
    /// settles on its end and the Finish row shows under it.
    func log(_ set: PlannedSet, of row: RoutineExercise) {
        // A log during a move, as VoiceOver's action can send, would start a second move whose
        // state the first one's end tears down.
        guard let workout = session.workout, !isMovingOn else { return }
        let next = routine.nextSet(after: workout.logging(set, of: row, at: .now).sets)
        guard next?.row != set.row else {
            // Logged as the key comes back to the start, so the line rolls with it.
            Task {
                try? await Task.sleep(for: .seconds(SetMotion.keyReturn), tolerance: .zero)
                withAnimation(.snappy(duration: SetMotion.roll)) { session.log(set, of: row) }
            }
            return
        }
        let target = next.flatMap { landing(on: $0.row, leaving: row.id) }
        guard !reduceMotion else {
            return crossfade(scrollingTo: target ?? scrollBeat.scrolledY) {
                session.log(set, of: row)
                if next != nil {
                    landings += 1
                }
            }
        }
        guard let next else { return logLast(set, of: row) }
        noteRestingPitch(of: next.row)
        let rows = routine.exercises.map(\.id)
        let isUp = (rows.firstIndex(of: next.row) ?? 0) < (rows.firstIndex(of: row.id) ?? 0)
        // At a superset round's end, the round just done rolls to the next once the first member
        // has grown to show it.
        let held = isUp && next.round != set.round && routine.isInSuperset(next.row)
            ? focus(of: row, on: set).progress : nil
        let way: SetMotion.Way = isUp ? .loop : .down
        isMovingOn = true
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
            session.log(set, of: row)
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

    /// A move's landing, with its tick and the node lighting under the pulse's plop, the round's
    /// roll once the next row shows it, then the move's end, timed from the log by design: nothing is
    /// waited for. With no `target` worked out ahead, as after a relaunch, the list lands after.
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
            }
            try? await Task.sleep(
                for: .seconds(SetMotion.move(way) - SetMotion.roundRoll(way)),
                tolerance: .zero,
            )
            exerciseMove = nil
            isMovingOn = false
            letRoomGo()
            if target == nil {
                withAnimation(.snappy(duration: SetMotion.roll), scrollToCurrent)
            }
        }
    }

    /// The workout's last planned set: the parts go, and the row closes back as the list settles
    /// on its end, in one motion, the Finish row fading in under it once the row is mostly
    /// closed. The room under the end that landed the row under the bar closes on the same curve,
    /// and the list's end stays where it shows as the content shortens, so what is above it moves
    /// down, once, and never back.
    private func logLast(_ set: PlannedSet, of row: RoutineExercise) {
        isMovingOn = true
        withTransaction(\.disablesAnimations, true) {
            closingRoomTop = currentPlace?.landingY ?? scrollBeat.scrolledY
        }
        withAnimation(SetMotion.shifting) {
            session.log(set, of: row)
            closingRoomTop = 0
        }
        Task {
            try? await Task.sleep(
                for: .seconds(SetMotion.shiftStart + SetMotion.shift),
                tolerance: .zero,
            )
            closingRoomTop = nil
            isMovingOn = false
            letRoomGo()
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

    /// Whether Start shows: with exercises to start, and out of a workout but for its going.
    var showsStart: Bool {
        !routine.exercises.isEmpty && !isStartAway && (session.workout == nil || isStarting)
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

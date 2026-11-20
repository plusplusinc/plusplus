import DesignSystem
import SwiftUI
import WorkoutStore

/// The rest between two exercises, after the last set of one, when the routine stores a rest
/// after it. While the exercise is current, its caption line's end says the rest that will follow
/// the set, "then rest 1:00" (`afterText(for:)`). The rest is a stop on the way: logging the last
/// set plays a move to the next exercise with the rest as its destination (`RailStop.rest(in:)`),
/// every timing and curve a move's (`SetMotion`): the pulse shoots down and lands level with the
/// word "Rest", plops and wiggles, and on the shift's curve the row closes to a done row and the
/// rest opens under it (`RestBlock`), the list staying where it is, as the next exercise grows a
/// step and shows its equipment (`nextUp`). Through the rest the dot waits there, the current
/// node's size and steady green, with nothing on the rail to mark the place (`restDotRow`); the
/// bar under the countdown shows how far through it is (`RestProgress`). As the countdown reaches
/// 0 the same move plays from the rest to the next exercise's node, the next exercise opening as
/// the dot leaves (`SetMotion.leavingRest`).
///
/// In a superset only a round's last member rests. With a round left, the rest opens above the
/// first member (`restRow(of:in:)`): the pulse runs up the loop and on up the rail to the word,
/// the list scrolling it under the bar from the tap (`SetMotion.toRestAbove`), and at 0 the dot
/// moves down to the first member. After the last round it opens under the last member.
///
/// Through any rest the key at the bottom swaps, as keys swap, for −15 s and +15 s (`RestKeys`),
/// the + above it staying put. −15 s with less than 15 s left ends the rest; + and − glide the bar
/// and turn the countdown, the dot staying put. Taps on them while the rest is still coming in,
/// as a double tap's second on Log set, do nothing. There is no Skip. With Reduce Motion, each
/// move is one crossfade, the dot at the word through the rest.
///
/// Between two sets of one plain exercise, the rest takes the figures' slot (`SetRest`); done one
/// side at a time, after a set's second side, never between its sides. With the same bar, from
/// the tap, everything the log changes on one curve (`SetMotion.restSwap`), and the exercise's
/// node stays steady green; with Reduce Motion it swaps in and out at once. Not yet: a relaunch
/// or a return from the background mid-rest. The rest's taps are kept in memory only.
extension RoutineScreen {
    /// For the UI tests, every rest's length (`-seedRest`); nil in a release build.
    var restOverride: Int? {
        #if DEBUG
        LaunchOptions.restOverride
        #else
        nil
        #endif
    }

    /// Whether the screen rests between exercises.
    var isResting: Bool {
        phase.resting != nil
    }

    /// The rest running after the last set, as stored, while the screen rests.
    var resting: WorkoutRest? {
        isResting ? live?.rest(override: restOverride) : nil
    }

    /// The rest as drawn, with the workout it runs on: the one running, or the one End came in
    /// until the list leaves it (`WorkoutPhase.drawnRest`).
    var drawnResting: (rest: WorkoutRest, workout: Workout)? {
        guard phase.drawnRest != nil, let shown, let rest = shown.rest(override: restOverride)
        else { return nil }
        return (rest, shown.workout)
    }

    /// Whether logging `set`, already stored, leading to `step`, rests first: on to another
    /// exercise down the rail from a plain row, with a rest after it; or on to the same plain
    /// row's next set, with a rest between its sets: after a set's last side when it is done one
    /// side at a time, never between its sides.
    func rests(after set: PlannedSet, leadingTo step: LiveWorkout.Step) -> Bool {
        switch step {
        case let .nextExercise(_, isBack, _) where !isBack || routine.isInSuperset(set.row):
            break
        case .nextSet where routine.restBetweenSets(after: set) != nil:
            break
        default:
            return false
        }
        return live?.rest(override: restOverride) != nil
    }

    /// The rest's opening, from the log: the dot leaves now, and as it does the row closes and
    /// the rest opens, on a close's curve. Between two sets of one exercise, from the tap, the
    /// rest and the figures swap in their slot as the segment turns and the line rolls on.
    func startRest() {
        if phase.resting?.isWithinExercise == true {
            // With Reduce Motion, at once: the rest swaps in with no ease.
            guard !reduceMotion else {
                phase.show()
                phase.settleRest()
                return
            }
            withAnimation(SetMotion.restSwap) { phase.show() }
            return sequence.run {
                try await beat(until: ContinuousClock.now + .seconds(SetMotion.roll))
                phase.settleRest()
            }
        }
        guard let rest = phase.resting, let live, let row = restRow(of: rest, in: live.workout)
        else { return }
        // Back up a superset's loop, the round's rest opens above its first member, maybe out of
        // sight: the list scrolls it under the bar from the tap, on the dot's way there.
        let way = SetMotion.Way(isBack: rest.isBack)
        let target = rest.isBack ? landing(on: row, leaving: rest.set.row) : nil
        withTransaction(\.disablesAnimations, true) {
            isMakingRoom = true
            endFollow = nil
            if let target {
                growthLift = target - scrollBeat.scrolledY
                scrollPosition.scrollTo(y: target)
            }
        }
        guard !reduceMotion else {
            // One crossfade into the rest, the dot at its word.
            beginCrossfade(scrollingTo: target ?? scrollBeat.scrolledY)
            return sequence.run {
                try await crossfade {
                    phase.show()
                    phase.landRest()
                    landings += 1
                }
                phase.settleRest()
                endRest()
            }
        }
        // A move to the next exercise with the rest as its destination: the same pulse, hold, and
        // shift, the row left closing and the rest opening on the shift's curve. The list stays
        // where it is, but for a round's rest above.
        withAnimation(SetMotion.moving(way)) {
            phase.show()
        }
        withAnimation(SetMotion.toRestAbove) { growthLift = 0 }
        railPulse = RailPulse(
            from: .node(rest.set.row),
            to: .rest(in: row),
            way: way,
            run: (railPulse?.run ?? 0) + 1,
        )
        sequence.run {
            let start = ContinuousClock.now
            try await beat(until: start + .seconds(SetMotion.landing(way)))
            landings += 1
            // At once, under the plop: the dot waiting at the rest is the plop's size and green.
            withTransaction(\.disablesAnimations, true) {
                phase.landRest()
            }
            try await beat(until: start + .seconds(SetMotion.move(way)))
            phase.settleRest()
            // A rest ended while the move into it played goes on now.
            endRest()
        }
    }

    /// The row whose rest the dot waits at: from the pulse's landing there until the next one
    /// sets off from it.
    var restDotRow: RoutineExercise.ID? {
        guard let rest = phase.drawnRest, !rest.isWithinExercise, rest.beat >= .landed,
              let shown
        else { return nil }
        return restRow(of: rest, in: shown.workout)
    }

    /// The rest is over: the move to the next exercise plays as one with no rest from its log,
    /// its pulse setting off from the dot.
    func endRest() {
        guard let rest = phase.resting, let workout = session.workout, let next = live?.currentSet,
              resting?.isOver(atClock: workout.clock(at: .now)) ?? true
        else { return }
        if rest.isWithinExercise {
            // The next set's figures swap back into their slot as the line rolls on, and Log set
            // comes back in place with them, taking a log once they are up.
            guard rest.beat < .returning else { return }
            guard !reduceMotion else {
                phase.endRest()
                phase.settleReturn()
                return
            }
            withAnimation(SetMotion.restSwap) { phase.endRest() }
            return sequence.run {
                try await beat(until: ContinuousClock.now + .seconds(SetMotion.roll))
                withTransaction(\.disablesAnimations, true) { phase.settleReturn() }
            }
        }
        guard rest.beat == .settled else { return }
        noteRestingPitch(of: next.row)
        // From the rest's height, not the row's pitch at rest, which a relaunch into the workout
        // never noted: with no target, the list landed in a second motion after the move.
        // Before a superset's next round the rest closes above the next row, in its own row,
        // whose top stays where it is: a short move down.
        let target = rest.isBack
            ? landing(on: next.row, leaving: rest.set.row)
            : landing(on: next.row, closingRestUnder: rest.set.row)
        guard !reduceMotion else {
            phase.endRest(moves: false)
            return crossfadeOn(to: next, scrollingTo: target)
        }
        withTransaction(\.disablesAnimations, true) {
            if let target {
                growthLift = target - scrollBeat.scrolledY
                scrollPosition.scrollTo(y: target)
            }
        }
        // As the dot leaves the word, not once it lands: the next exercise opens as the bar swaps
        // −15 s and +15 s back for the key.
        withAnimation(SetMotion.leavingRest) {
            phase.endRest()
            growthLift = 0
        }
        railPulse = RailPulse(
            from: .rest(in: restRow(of: rest, in: workout) ?? rest.set.row),
            to: .node(next.row),
            way: .down,
            run: (railPulse?.run ?? 0) + 1,
        )
        land(.down, scrollingTo: target)
    }

    /// −15 s or +15 s on the rest running, the bar gliding to its new fill; the dot stays put.
    /// Nothing while the rest is still coming in, so a double tap's second on Log set, landing on
    /// −15 s as it swaps in, changes nothing; nor once it is over.
    func adjustRest(by seconds: Int) {
        guard let rest = phase.resting, rest.beat < .returning,
              rest.beat >= (rest.isWithinExercise ? .settled : .landed),
              let live, let last = live.workout.sets.last, let next = live.currentSet
        else { return }
        let length = restOverride ?? routine.rest(after: last.planned, before: next)
        withAnimation(.snappy(duration: SetMotion.restGlide)) {
            session.adjustRest(by: seconds, length: length)
        }
    }

    /// The row a rest between exercises is drawn in, `workout` holding the set it follows: the
    /// row left, under its label; or, before a superset's next round, the first member's, above
    /// its label (`isBack`).
    func restRow(of rest: WorkoutPhase.Resting, in workout: Workout) -> RoutineExercise.ID? {
        rest.isBack ? LiveWorkout(routine: routine, workout: workout).currentSet?.row : rest.set.row
    }

    /// The rest in `id`'s row, under its label or `above` it: open once it shows, or none.
    func restBlock(in id: RoutineExercise.ID, above: Bool) -> RestBlock {
        if let rest = phase.drawnRest, !rest.isWithinExercise, rest.beat >= .shown,
           rest.isBack == above, let (resting, workout) = drawnResting,
           restRow(of: rest, in: workout) == id
        {
            return RestBlock(
                stage: .open,
                length: resting.length,
                ends: workout.date(ofClock: resting.endClock),
                pausedLeft: workout.isPaused
                    ? resting.remaining(atClock: workout.clock(at: .now)) : nil,
            )
        }
        // Ended mid-rest, its room closes with the list showing the time it had.
        if let (rest, workout) = phase.restLeft, !rest.isWithinExercise, rest.isBack == above,
           restRow(of: rest, in: workout) == id,
           let left = LiveWorkout(routine: routine, workout: workout).rest(override: restOverride)
        {
            return RestBlock(
                stage: .none,
                length: left.length,
                ends: workout.date(ofClock: left.endClock),
                pausedLeft: left.remaining(atClock: workout.clock(at: .now)),
            )
        }
        return RestBlock(stage: .none, length: 0)
    }

    /// The rest between two sets of the current exercise, `id`, in its figures' slot: running
    /// from the log until its end, then over as it swaps back; else unseen, keeping the slot as
    /// tall as the rest for every set of an exercise that rests between them. Nil for any other
    /// row, and an exercise with no rest between its sets.
    func setRest(of id: RoutineExercise.ID, current: RoutineExercise.ID?) -> SetRest? {
        guard id == current, let shown, let gap = routine.restBetweenSets(of: id),
              (restOverride ?? gap) > 0
        else { return nil }
        if let within = phase.drawnRest, within.isWithinExercise, within.beat >= .shown,
           let (resting, workout) = drawnResting
        {
            let isOver = within.beat == .returning
            return SetRest(
                isRunning: !isOver,
                length: resting.length,
                ends: workout.date(ofClock: resting.endClock),
                pausedLeft: workout.isPaused
                    ? resting.remaining(atClock: workout.clock(at: .now)) : nil,
                isOver: isOver,
                turns: within.beat == .settled,
            )
        }
        return SetRest(isRunning: false, length: restOverride ?? gap)
    }

    /// What follows `set` at its caption line's end, before it is logged: "then rest
    /// 1:00" where a rest will run after it, as `rests(after:leadingTo:)` decides once it is;
    /// "last set" on the workout's last; else nothing.
    func afterText(for set: PlannedSet, in shown: LiveWorkout) -> String? {
        let step = shown.step(logging: set)
        let gap: Int
        switch step {
        case .last:
            return String(localized: "last set")
        case .nextSet:
            gap = routine.restBetweenSets(after: set) ?? 0
        case let .nextExercise(next, isBack, _) where !isBack || routine.isInSuperset(set.row):
            // In a superset, none within a round: only its last member rests.
            gap = routine.rest(after: set, before: next)
        default:
            return nil
        }
        // A rest of 0 s runs no rest, so none is promised: it read "then rest 0:00".
        // The tests' length stands in only where the routine rests, never between two sides.
        let length = gap > 0 ? restOverride ?? gap : 0
        guard length > 0 else { return nil }
        return thenRestText(length)
    }

    /// "then rest 1:00", for a rest of `seconds`.
    func thenRestText(_ seconds: Int) -> String {
        let length = Duration.seconds(seconds)
            .formatted(.time(pattern: .minuteSecond).locale(locale))
        return String(localized: "then rest \(length)")
    }

    /// What the rest's watch waits on: a + or −, a pause, or a resume starts it again.
    var restWatch: RestWatch? {
        guard let resting, let workout = session.workout else { return nil }
        return RestWatch(endClock: resting.endClock, isPaused: workout.isPaused)
    }

    /// Sleeps to the rest's end, then ends it. Never while paused.
    func watchRest() async {
        guard let resting, let workout = session.workout, !workout.isPaused else { return }
        let left = resting.remaining(atClock: workout.clock(at: .now))
        do {
            try await Task.sleep(for: .seconds(left), tolerance: .zero)
        } catch {
            return
        }
        endRest()
    }

    /// A row's content: its label, and under it its rest, as part of the row, so the row's own
    /// stretch of rail runs through the room it opens.
    func rowContent(
        _ item: RoutineExercise,
        current: RoutineExercise.ID?,
        on set: PlannedSet?,
        parts: RowParts?,
    ) -> some View {
        LabelWithRest(
            label: rowLabel(item, current: current, on: set, parts: parts),
            rest: parts?.restAfter ?? RestBlock(stage: .none, length: 0),
            restAbove: parts?.restBefore ?? RestBlock(stage: .none, length: 0),
            onRestHeight: { rowFrames.restHeights[item.id] = $0 },
        )
    }

    /// Each row's bars, rests, and state in the workout, for the rows' closure to hold as values.
    /// Worked out in the closure, the rests read the stored workout live but the phase as the
    /// closure was made: a row redrawn on its own as a log was stored read the set in the workout
    /// with the phase from before the log, which hides it, and the last set's rest line went into
    /// the numbers' room for a pass, the rows below jumping up 24 pt as it came back out.
    func rowParts(
        in shown: LiveWorkout?,
        current: RoutineExercise.ID?,
    ) -> [RoutineExercise.ID: RowParts] {
        let bars = rowBars(in: shown)
        let finished = Set(shown?.finishedRows ?? [])
        let after = shown.flatMap { shown in
            shown.currentSet.flatMap { afterText(for: $0, in: shown) }
        }
        // Resting between two exercises, the next one grows a step once the rest shows, and
        // stays grown through the move out of the rest until it opens: dropped as the rest
        // ended, it shrank back and lost its equipment for a frame before growing again.
        let isRestingBetween = phase.drawnRest.map { !$0.isWithinExercise && $0.beat >= .shown }
            ?? (phase.move?.isFromRest == true)
        let nextUp = isRestingBetween ? shown?.currentSet?.row : nil
        return routine.exercises.reduce(into: [:]) { parts, item in
            parts[item.id] = RowParts(
                bars: bars[item.id],
                restBetween: setRest(of: item.id, current: current),
                restAfter: restBlock(in: item.id, above: false),
                restBefore: restBlock(in: item.id, above: true),
                isDone: finished.contains(item.id),
                nextUp: item.id == nextUp ? [item.exercise].equipment.map(\.name) : nil,
                after: item.id == current ? after : nil,
            )
        }
    }

    /// Scrolls the current exercise's row up to just under the bar.
    func scrollToCurrent() {
        if let place = currentPlace {
            scrollPosition.scrollTo(y: place.landingY)
        }
    }
}

struct RestWatch: Equatable {
    let endClock: Double
    let isPaused: Bool
}

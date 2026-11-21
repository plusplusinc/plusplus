import DesignSystem
import SwiftUI
import WorkoutStore

/// The rest between two exercises, after the last set of one, when the workout stores a rest
/// after it. While the exercise is current, its caption line's end says the rest that will follow
/// the set, "then rest 1:00" (`afterText(for:)`). The rest is a stop on the way: logging the last
/// set plays a move to the next exercise with the rest as its destination (`RailStop.rest(in:)`),
/// with a move's pulse (`SetMotion`): from the tap the row closes to a done row and the rest opens
/// under it (`RestBlock`), the list staying where it is, as the next exercise grows a step and
/// shows its equipment (`nextUp`), all still by the time the pulse, shooting down, reaches the
/// word "Rest", where it plops and wiggles (`SetMotion.aroundRest(_:)`), short of the next
/// exercise's node. Through the rest the dot waits there, the current node's size and steady
/// green, with nothing on the rail to mark the place (`restDotRow`). As the countdown reaches 0
/// the same move plays from the rest to the next exercise's node, the rest closing and the
/// exercise opening at once.
///
/// In a superset only a round's last member rests. With a round left, the rest opens above the
/// first member (`restRow(of:in:)`): the pulse runs up the loop and on up the rail to the word,
/// the list scrolling it under the bar, the row left closing, and the rest opening, all from the
/// tap, and at 0 the dot moves down to the first member; its count stands as far above that
/// member's name as a rest between exercises stands above the next one's (`LabelWithRest`).
/// After the last round it opens under the last member.
///
/// Through any rest the key at the bottom swaps, as keys swap, for Skip rest, wide, gray, filling
/// with the done purple from its leading edge as the rest runs (`restKeyFill`), and +15 s beside
/// it (`CountKeys`), the + above it staying put. There is no bar under the countdown. Skip rest
/// ends the rest at the tap as running out does (`skipRest()`); +15 s steps the fill back and
/// turns the countdown, the dot staying put. A pause grays the countdown and the fill. Taps on
/// them while the rest is still coming in, as a double tap's second on Log set, do nothing. With
/// Reduce Motion, each move is one crossfade, the dot at the word through the rest.
///
/// Between two sets of one plain exercise, the rest takes the figures' slot (`SetRest`); done one
/// side at a time, after a set's second side, never between its sides. From the tap, everything
/// the log changes moves on one curve (`SetMotion.restSwap`), and the exercise's node stays
/// steady green; with Reduce Motion it crossfades in and out.
///
/// A rest runs on the workout's clock from its log, its taps kept with the set logged
/// (`LiveWorkout.extendingRest(by:override:at:)`, `skippingRest(override:at:)`), so a pause
/// stops it, and a relaunch or a return from the background opens in it, drawn and settled, at
/// the time left, or past its end on the next set (`WorkoutPhase(resuming:restOverride:at:)`).
/// VoiceOver hears "Rest" and its length as it starts (`announceRest()`), reads the countdown as
/// its own element, with the time left, and the keys as "Skip rest", its value the time left,
/// and "Plus 15 seconds". At its end the phone taps once, heavy (`restEnds`).
extension WorkoutScreen {
    /// For the UI tests, every rest's length (`-seedRest`); nil in a release build.
    var restOverride: Int? {
        Self.restOverride
    }

    static var restOverride: Int? {
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
    var drawnResting: (rest: WorkoutRest, loggedWorkout: LoggedWorkout)? {
        guard phase.drawnRest != nil, let shown, let rest = shown.rest(override: restOverride)
        else { return nil }
        return (rest, shown.loggedWorkout)
    }

    /// The rest's opening, from the log: the dot leaves now, and as it does the row closes and
    /// the rest opens, on a close's curve. Between two sets of one exercise, from the tap, the
    /// rest and the figures swap in their slot as the segment turns and the line rolls on.
    func startRest() {
        announceRest()
        if phase.resting?.isWithinExercise == true {
            return startRestBetweenSets()
        }
        guard let rest = phase.resting, let live,
              let row = restRow(of: rest, in: live.loggedWorkout)
        else { return }
        // Back up a superset's loop, the round's rest opens above its first member, maybe out of
        // sight: the list scrolls it under the bar from the tap, on the dot's way there. Its pitch
        // at rest is measured with no rest around it (`restingContent(_:in:)`): measured at the
        // rest's end, it held the rest, and the next move overshot.
        let way = SetMotion.Way(isBack: rest.isBack)
        let target = rest.isBack ? landing(on: row, leaving: rest.set.row) : nil
        withTransaction(\.disablesAnimations, true) {
            isMakingRoom = true
            endFollow = nil
            if let target {
                liftScroll(to: target)
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
        // A move to the next exercise with the rest as its destination: the same pulse, the row
        // left closing and the rest opening from the tap, still by the time the pulse gets there.
        // A round's rest above opens with the scroll: on the shift's curve, it came in all at
        // once, a beat after the scroll stopped.
        withAnimation(SetMotion.aroundRest(way)) {
            phase.show()
            growthLift = 0
        }
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

    /// Between two sets of one exercise, from the tap, the rest and the figures swap in their
    /// slot. With Reduce Motion, the list's crossfade, as every move has: set at once, the rest
    /// cut in on one frame.
    private func startRestBetweenSets() {
        guard !reduceMotion else {
            beginCrossfade(scrollingTo: scrollBeat.scrolledY)
            return sequence.run {
                try await crossfade { phase.show() }
                phase.settleRest()
                // A rest ended while it faded in goes on now.
                endRest()
            }
        }
        withAnimation(SetMotion.restSwap) { phase.show() }
        sequence.run {
            try await beat(until: ContinuousClock.now + .seconds(SetMotion.roll))
            phase.settleRest()
        }
    }

    /// Tells VoiceOver a rest has started, and how long it is, "Rest, 1 minute": its focus stays
    /// on the key, which swaps for Skip rest and +15 s.
    private func announceRest() {
        guard let resting else { return }
        let length = RestBlock.spoken(Double(resting.length), locale: locale)
        AccessibilityNotification.Announcement(String(localized: "Rest, \(length)")).post()
    }

    /// The row whose rest the dot waits at: from the pulse's landing there until the next one
    /// sets off from it.
    var restDotRow: WorkoutExercise.ID? {
        guard let rest = phase.drawnRest, !rest.isWithinExercise, rest.beat >= .landed,
              let shown
        else { return nil }
        return restRow(of: rest, in: shown.loggedWorkout)
    }

    /// The rest is over: the move to the next exercise plays as one with no rest from its log,
    /// its pulse setting off from the dot.
    func endRest() {
        guard let rest = phase.resting, let loggedWorkout = session.loggedWorkout,
              let next = live?.currentSet,
              resting?.isOver(atClock: loggedWorkout.clock(at: .now)) ?? true
        else { return }
        // A timed set next counts from the rest's end, in the same update as the rest ends.
        session.beginCount(override: restOverride)
        if rest.isWithinExercise {
            // The next set's figures swap back into their slot as the line rolls on, and Log set
            // comes back in place with them, taking a log once they are up.
            guard rest.beat < .returning, !isCrossfading else { return }
            restEnds += 1
            guard !reduceMotion else {
                beginCrossfade(scrollingTo: scrollBeat.scrolledY)
                return sequence.run {
                    try await crossfade { phase.endRest() }
                    phase.settleReturn(on: arrivingCount())
                }
            }
            withAnimation(SetMotion.restSwap) { phase.endRest() }
            return sequence.run {
                try await beat(until: ContinuousClock.now + .seconds(SetMotion.roll))
                withTransaction(\.disablesAnimations, true) {
                    phase.settleReturn(on: arrivingCount())
                }
            }
        }
        // Not again while its fade waits for its turn to start.
        guard rest.beat == .settled, !isCrossfading else { return }
        restEnds += 1
        // From the rest's height, not the row's pitch at rest, which a relaunch into the rest never
        // measured (the list landed in a second motion). Before a superset's next round the rest
        // closes above
        // the next row, in its own row, whose top stays where it is: a short move down.
        let target = rest.isBack
            ? landing(on: next.row, leaving: rest.set.row)
            : landing(on: next.row, closingRestUnder: rest.set.row)
        guard !reduceMotion else {
            return crossfadeOn(to: next, scrollingTo: target, endingRest: true)
        }
        if let target {
            withTransaction(\.disablesAnimations, true) { liftScroll(to: target) }
        }
        // The next exercise opens as the dot leaves the word; the list scrolls it under the bar
        // once the dot has landed: from the tap, the dot rose under the bar and came back down.
        withAnimation(SetMotion.aroundRest(.down)) { phase.endRest() }
        withAnimation(SetMotion.moving(.down)) { growthLift = 0 }
        railPulse = RailPulse(
            from: .rest(in: restRow(of: rest, in: loggedWorkout) ?? rest.set.row),
            to: .node(next.row),
            way: .down,
            run: (railPulse?.run ?? 0) + 1,
        )
        land(.down, scrollingTo: target)
    }

    /// Scrolls to `target` at once, the list drawn lifted back to where it was, for the move's
    /// own animation to run the lift to 0 (`GrowthLift`). In a transaction with animations off.
    func liftScroll(to target: CGFloat) {
        growthLift = target - scrollBeat.scrolledY
        scrollPosition.scrollTo(y: target)
    }

    /// The row a rest between exercises is drawn in, `loggedWorkout` holding the set it follows:
    /// the row left, under its label; before a superset's next round, the first member's, above it.
    func restRow(of rest: WorkoutPhase.Resting, in loggedWorkout: LoggedWorkout)
        -> WorkoutExercise.ID?
    {
        rest.isBack
            ? LiveWorkout(workout: workout, loggedWorkout: loggedWorkout).currentSet?.row
            : rest.set.row
    }

    /// The rest between exercises as drawn: the row it is in, whether `above` the row's label, and
    /// the block, open once it shows; worked out once for all the rows. Nil with none drawn.
    func drawnRestBlock() -> DrawnRestBlock? {
        if let rest = phase.drawnRest, !rest.isWithinExercise, rest.beat >= .shown,
           let (resting, loggedWorkout) = drawnResting,
           let row = restRow(of: rest, in: loggedWorkout)
        {
            let (ends, pausedLeft) = Self.times(of: resting, on: loggedWorkout, end: phase.drawnEnd)
            let block = RestBlock(
                stage: .open,
                length: resting.length,
                ends: ends,
                pausedLeft: pausedLeft,
                isPaused: loggedWorkout.isPaused,
            )
            return DrawnRestBlock(row: row, above: rest.isBack, block: block)
        }
        // Ended mid-rest, its room closes with the list showing the time it had.
        if let (rest, loggedWorkout) = phase.restLeft, !rest.isWithinExercise,
           let row = restRow(of: rest, in: loggedWorkout),
           let left = LiveWorkout(workout: workout, loggedWorkout: loggedWorkout)
               .rest(override: restOverride)
        {
            let (ends, pausedLeft) = Self.times(of: left, on: loggedWorkout, stopped: true)
            let block = RestBlock(
                stage: .none,
                length: left.length,
                ends: ends,
                pausedLeft: pausedLeft,
            )
            return DrawnRestBlock(row: row, above: rest.isBack, block: block)
        }
        return nil
    }

    /// When `rest` ends, on `workout`'s clock running on from now, and the seconds it has left
    /// where that clock stands still: paused, ended, or `stopped`, so the countdown holds; or
    /// where it stood at `end`, End's choice (`WorkoutPhase.drawnEnd`), as the list shrinks out
    /// of the workout End took: running on through the shrink, the count went on with a
    /// second's roll as it went.
    static func times(
        of rest: WorkoutRest,
        on loggedWorkout: LoggedWorkout,
        stopped: Bool = false,
        end: Date? = nil,
    ) -> (ends: Date, pausedLeft: Double?) {
        let holds = stopped || end != nil || loggedWorkout.isPaused || !loggedWorkout.isInProgress
        return (
            loggedWorkout.date(ofClock: rest.endClock),
            holds ? rest.remaining(atClock: loggedWorkout.clock(at: end ?? .now)) : nil,
        )
    }

    /// The rest between two sets of the current exercise, `id`, in its figures' slot: running
    /// from the log until its end, then over as it swaps back; else unseen, keeping the slot as
    /// tall as the rest for every set of an exercise that rests between them. Nil for any other
    /// row, and an exercise with no rest between its sets.
    func setRest(of id: WorkoutExercise.ID, current: WorkoutExercise.ID?) -> SetRest? {
        guard id == current, let shown, let gap = workout.restBetweenSets(of: id),
              (restOverride ?? gap) > 0
        else { return nil }
        if let within = phase.drawnRest, within.isWithinExercise, within.beat >= .shown,
           let (resting, loggedWorkout) = drawnResting
        {
            let isOver = within.beat == .returning
            let (ends, pausedLeft) = Self.times(of: resting, on: loggedWorkout, end: phase.drawnEnd)
            return SetRest(
                isRunning: !isOver,
                length: resting.length,
                ends: ends,
                pausedLeft: pausedLeft,
                isOver: isOver,
                turns: within.beat == .settled,
                isPaused: loggedWorkout.isPaused,
            )
        }
        return SetRest(isRunning: false, length: restOverride ?? gap)
    }

    /// What follows `set` at its caption line's end, before it is logged: "then rest 1:00" where
    /// a rest will run after it (`LiveWorkout.restLength(after:leadingTo:override:)`), never for
    /// a rest of 0 s, which runs none; "last set" on the workout's last; else nothing. `earlier`,
    /// sets taken as logged first.
    func afterText(
        for set: PlannedSet,
        in shown: LiveWorkout,
        after earlier: [PlannedSet] = [],
    ) -> CaptionEnd? {
        let step = shown.step(logging: set, after: earlier)
        guard step != .last else {
            let last = String(localized: "last set")
            return CaptionEnd(text: last, spoken: last)
        }
        let length = shown.restLength(after: set, leadingTo: step, override: restOverride)
        return length > 0 ? thenRest(length) : nil
    }

    /// "then rest 1:00", for a rest of `seconds`, and in words, "then rest 1 minute".
    func thenRest(_ seconds: Int) -> CaptionEnd {
        let clock = RestBlock.text(Double(seconds), locale: locale)
        let words = RestBlock.spoken(Double(seconds), locale: locale)
        return CaptionEnd(
            text: String(localized: "then rest \(clock)"),
            spoken: String(localized: "then rest \(words)"),
        )
    }

    /// What the rest's watch waits on: +15 s, a skip, a pause, or a resume starts it again.
    var restWatch: RestWatch? {
        guard let resting, let loggedWorkout = session.loggedWorkout else { return nil }
        return RestWatch(endClock: resting.endClock, isPaused: loggedWorkout.isPaused)
    }

    /// Sleeps to the rest's end, then ends it; never while paused. A rest gone while the screen
    /// rests, its row's rest set to 0 or the row deleted, ends at once. The rest's end is on the
    /// workout's clock, which runs on the wall clock, and the sleep on the device's: woken with
    /// time left, as after the wall clock stepped back, it sleeps on to the end.
    func watchRest() async {
        guard isResting else { return }
        while let resting {
            guard let loggedWorkout = session.loggedWorkout, !loggedWorkout.isPaused else { return }
            let left = resting.remaining(atClock: loggedWorkout.clock(at: .now))
            guard left > 0 else { break }
            guard await (try? Task.sleep(for: .seconds(left), tolerance: .zero)) != nil
            else { return }
        }
        endRest()
    }
}

/// The rest between exercises as drawn, in `row`, under its label or `above` it.
struct DrawnRestBlock {
    let row: WorkoutExercise.ID
    let above: Bool
    let block: RestBlock

    /// The block in `id`'s row, under its label or `above` it: this one there, else closed.
    func block(in id: WorkoutExercise.ID, above: Bool) -> RestBlock {
        id == row && above == self.above ? block : .closed
    }
}

struct RestWatch: Equatable {
    let endClock: Double
    let isPaused: Bool
}

import DesignSystem
import SwiftUI
import WorkoutStore

/// The rest between two exercises, after the last set of one, when the routine stores a rest
/// after it. While the exercise is current, the rest that will follow it shows as a quiet line
/// under it (`RestBlock.Stage.line`). Logging its last set plays two motions at once: the dot
/// leaves the node as a pulse does and eases out into the top of the rest's bar, thinning to it
/// and turning blue (`RailTravel`), as, on a close's curve, the row closes to a done row and the
/// line grows in place into the rest (`RestBlock.Stage.open`), so the rows below move once. The
/// blue fills the bar at one speed for the whole rest, steady. As the countdown reaches 0 the
/// move goes on as a move with no rest does, its pulse setting off from the fill, where it is and
/// at its speed, gathering back into the green dot (`RailPulse.afterRest`): the slide into the
/// next node, the plop, and the next exercise growing as the rest closes. The key is gone through
/// the rest, its room kept. −15 s with less than 15 s left ends it; + and − glide the fill to its
/// new place. There is no Skip.
///
/// Between two sets of one plain exercise, the rest takes the set's numbers' place (`SetRest`)
/// and a bar beside it fills blue (`SetRestBar`), the exercise's node steady green; with Reduce
/// Motion it swaps in and out at once.
///
/// Not yet: supersets (their members go straight on), pause beyond the countdown and fill
/// holding, a relaunch or a return from the background mid-rest, and Reduce Motion between
/// exercises (its crossfade goes straight on). The rest's taps are kept in memory only.
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

    /// Whether logging `set`, already stored, leading to `step`, rests first: on to another
    /// exercise down the rail from a plain row, with a rest after it; or on to the same plain
    /// row's next set, done on both sides at once, with a rest between its sets.
    func rests(after set: PlannedSet, leadingTo step: LiveWorkout.Step) -> Bool {
        switch step {
        case .nextExercise(_, false, _) where !routine.isInSuperset(set.row):
            break
        case .nextSet where set.side == nil && routine.restBetweenSets(of: set.row) != nil:
            break
        default:
            return false
        }
        return live?.rest(override: restOverride) != nil
    }

    /// The rest's opening, from the log: the dot leaves now, and as it does the row closes and
    /// the rest opens, on a close's curve. Between two sets of one exercise, the set is held as
    /// a set logged is, then the rest and the next set swap places as the line rolls on.
    func startRest() {
        if phase.resting?.isWithinExercise == true {
            return sequence.run {
                let start = ContinuousClock.now
                // With Reduce Motion, at once: the rest swaps in with no ease.
                guard !reduceMotion else {
                    phase.show()
                    phase.settleRest()
                    return
                }
                try await beat(until: start + .seconds(SetMotion.heldRoll))
                withAnimation(.snappy(duration: SetMotion.roll)) { phase.show() }
                try await beat(until: start + .seconds(SetMotion.heldRoll + SetMotion.roll))
                phase.settleRest()
            }
        }
        withTransaction(\.disablesAnimations, true) {
            isMakingRoom = true
            endFollow = nil
            restHandoff = nil
        }
        withAnimation(SetMotion.closing) {
            phase.show()
        }
        sequence.run {
            let start = ContinuousClock.now
            try await beat(until: start + .seconds(SetMotion.closeStart + SetMotion.close))
            phase.settleRest()
        }
    }

    /// The rest is over: the move to the next exercise plays as one with no rest from its log,
    /// its pulse setting off from the dot.
    func endRest() {
        guard let rest = phase.resting, let workout = session.workout, let next = live?.currentSet,
              resting?.isOver(atClock: workout.clock(at: .now)) ?? true
        else { return }
        if rest.isWithinExercise {
            // The next set's numbers swap back into their place as the line rolls on, and the
            // key comes back once they are up.
            guard rest.beat < .returning else { return }
            guard !reduceMotion else {
                phase.endRest()
                phase.settleReturn()
                return
            }
            withAnimation(.snappy(duration: SetMotion.roll)) { phase.endRest() }
            return sequence.run {
                try await beat(until: ContinuousClock.now + .seconds(SetMotion.roll))
                withTransaction(\.disablesAnimations, true) { phase.settleReturn() }
            }
        }
        noteRestingPitch(of: next.row)
        let handoff = restHandoff ?? restTravel?.handoff(at: .now)
        restHandoff = nil
        let target = landing(on: next.row, leaving: rest.set.row)
        withTransaction(\.disablesAnimations, true) {
            if let target {
                growthLift = target - scrollBeat.scrolledY
                scrollPosition.scrollTo(y: target)
            }
        }
        withAnimation(SetMotion.moving(.down)) {
            phase.endRest()
            growthLift = 0
        }
        railPulse = RailPulse(
            from: rest.set.row,
            to: next.row,
            way: .down,
            run: (railPulse?.run ?? 0) + 1,
            afterRest: handoff,
        )
        land(.down, scrollingTo: target)
    }

    /// −15 s or +15 s on the rest running, the dot gliding to its new place.
    func adjustRest(by seconds: Int) {
        guard isResting, let live, let last = live.workout.sets.last, let next = live.currentSet
        else { return }
        let length = restOverride ?? routine.rest(after: last.planned, before: next)
        // Before the end moves: if this ends the rest, the pulse sets off from the dot as it is.
        let before = restTravel?.handoff(at: .now)
        withAnimation(.snappy(duration: SetMotion.restGlide)) {
            session.adjustRest(by: seconds, length: length)
        }
        if let workout = session.workout,
           resting?.isOver(atClock: workout.clock(at: .now)) ?? false
        {
            restHandoff = before
        }
    }

    /// The rest under `id`'s row: the line under the current exercise, the rest open under the
    /// row left once it shows, or none.
    func restBlock(under id: RoutineExercise.ID) -> RestBlock {
        if let rest = phase.resting, !rest.isWithinExercise, rest.beat >= .shown,
           rest.set.row == id, let resting, let workout = session.workout
        {
            return RestBlock(
                stage: .open,
                length: resting.length,
                ends: workout.date(ofClock: resting.endClock),
                pausedLeft: workout.isPaused
                    ? resting.remaining(atClock: workout.clock(at: .now)) : nil,
                onShorten: { adjustRest(by: -15) },
                onExtend: { adjustRest(by: 15) },
            )
        }
        // A rest between its sets has its own line, in its numbers' room (`setRest(of:current:)`).
        let ownsLine = setRest(of: id, current: currentID).map { $0.stage != .held } ?? false
        if id == currentID, !ownsLine,
           let length = shown?.restAfterCurrentExercise(override: restOverride)
        {
            return RestBlock(stage: .line, length: length)
        }
        return RestBlock(stage: .none, length: 0)
    }

    /// The rest between two sets of the current exercise, `id`, in its numbers' room: running
    /// from the swap until the swap back; coming during a set with one after it; else held, the
    /// room kept as tall as the rest for every set of an exercise that rests between them. Nil
    /// for any other row, and an exercise with no rest between its sets.
    func setRest(of id: RoutineExercise.ID, current: RoutineExercise.ID?) -> SetRest? {
        guard id == current, let shown, routine.restBetweenSets(of: id) != nil else { return nil }
        let next = shown.currentSet.map(nextSetLine) ?? ""
        let within = phase.resting.flatMap { $0.isWithinExercise ? $0 : nil }
        let workout = session.workout
        let ends = resting.flatMap { rest in workout.map { $0.date(ofClock: rest.endClock) } }
        if let within, within.beat >= .shown, within.beat < .returning, let resting, let workout {
            return SetRest(
                stage: .running,
                length: resting.length,
                next: next,
                ends: ends ?? .distantPast,
                pausedLeft: workout.isPaused
                    ? resting.remaining(atClock: workout.clock(at: .now)) : nil,
                onShorten: { adjustRest(by: -15) },
                onExtend: { adjustRest(by: 15) },
            )
        }
        let coming = shown.restAfterCurrentSet(override: restOverride)
        if within?.beat == .returning {
            // Swapping back into the last set, the line is the rest before the next exercise.
            return SetRest(
                stage: .coming,
                length: coming ?? shown.restAfterCurrentExercise(override: restOverride),
                next: next,
                ends: ends ?? .distantPast,
                isOver: true,
            )
        }
        if let coming {
            // Its end from the log, while it is still hidden, so the countdown comes up on its
            // time rather than turning to it from 0:00, as it did with no swap to hide it.
            return SetRest(stage: .coming, length: coming, next: next, ends: ends ?? .distantPast)
        }
        // At the last set, the line is the rest before the next exercise's, under the row; with
        // none, its room is kept, empty, so the row keeps its height.
        return shown.restAfterCurrentExercise(override: restOverride) == nil
            ? SetRest(stage: .coming, length: nil, next: next)
            : SetRest(stage: .held, length: nil)
    }

    /// The next set as the line under the rest reads it: "Set 2: 10 reps", "Set 2: 10 reps ·
    /// 50 lb".
    func nextSetLine(_ set: PlannedSet) -> String {
        guard let item = routine.exercises.first(where: { $0.id == set.row }) else { return "" }
        let figures = item.figures(side: set.side, locale: locale).map { figure in
            [figure.number, figure.unit].filter { !$0.isEmpty }.joined(separator: " ")
        }
        let round = set.round.formatted(.number.locale(locale))
        return "Set \(round): " + figures.joined(separator: " · ")
    }

    /// While the current exercise rests between its sets, the bar beside its rest that fills
    /// for the rest's length, from the log until the swap back is over: from the swap, as the
    /// rest comes up at the bar's top.
    private var setRestTravel: RailTravel<RoutineExercise.ID>? {
        guard let rest = phase.resting, rest.isWithinExercise, let workout = session.workout,
              let resting = live?.rest(override: restOverride), !resting.isBetweenExercises
        else { return nil }
        let starts = workout.date(ofClock: resting.startClock)
        return RailTravel(
            from: rest.set.row,
            to: rest.set.row,
            starts: starts.addingTimeInterval(reduceMotion ? 0 : SetMotion.heldRoll),
            ends: workout.date(ofClock: resting.endClock),
            heldAt: workout.pausedAt,
            betweenSets: rest.beat == .logged ? .coming : rest.beat == .returning ? .going : .shown,
        )
    }

    /// The dot crossing the rail for the rest, from the log, from the row left's node to the
    /// next's; between two sets, the bar beside the rest.
    var restTravel: RailTravel<RoutineExercise.ID>? {
        if let setRestTravel {
            return setRestTravel
        }
        guard let resting, resting.isBetweenExercises, let workout = session.workout
        else { return nil }
        return RailTravel(
            from: resting.after.row,
            to: resting.next.row,
            starts: workout.date(ofClock: resting.startClock),
            ends: workout.date(ofClock: resting.endClock),
            heldAt: workout.pausedAt,
        )
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
        bars: SetProgress?,
    ) -> some View {
        LabelWithRest(
            label: rowLabel(
                item,
                current: current,
                on: set,
                bars: bars,
                setRest: setRest(of: item.id, current: current),
            ),
            rest: restBlock(under: item.id),
        )
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

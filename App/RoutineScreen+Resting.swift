import DesignSystem
import SwiftUI
import WorkoutStore

/// The rest between two exercises, after the last set of one, when the routine stores a rest
/// after it. While the exercise is current, the rest that will follow it shows as a quiet line
/// under it (`RestBlock.Stage.line`). Logging its last set plays two motions at once: the dot
/// leaves the node as a pulse does and eases out, long and soft, into the rest's crawl
/// (`RailTravel`), as, on a close's curve, the row closes to a done row and the line grows in
/// place into the rest (`RestBlock.Stage.open`), so the rows below move once. The dot then
/// crawls its share of the stretch at one speed for the whole rest, its size held, its green
/// dimming and coming back once a second, full as the countdown turns. As the countdown reaches
/// 0 the move goes on as a move with no rest does, its pulse setting off from the dot, where it
/// is and at its speed (`RailPulse.afterRest`): the slide into the next node, the plop, and the
/// next exercise growing as the rest closes. The key is gone through the rest, its room kept. −15 s
/// with less
/// than 15 s left ends it; + and − glide the dot to its new place. There is no Skip.
///
/// Not yet: a rest between two sets of one exercise, supersets (their members go straight on),
/// pause beyond the countdown and dot holding, a relaunch or a return from the background
/// mid-rest, and Reduce Motion (its crossfade goes straight on). The rest's taps are kept in
/// memory only.
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
    /// exercise down the rail from a plain row, with a rest after it.
    func rests(after set: PlannedSet, leadingTo step: LiveWorkout.Step) -> Bool {
        guard case .nextExercise(_, false, _) = step, !routine.isInSuperset(set.row)
        else { return false }
        return live?.rest(override: restOverride) != nil
    }

    /// The rest's opening, from the log: the dot leaves now, and as it does the row closes and
    /// the rest opens, on a close's curve.
    func startRest() {
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
        if let rest = phase.resting, rest.beat >= .shown, rest.set.row == id,
           let resting, let workout = session.workout
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
        if id == currentID, let length = shown?.restAfterCurrentExercise(override: restOverride) {
            return RestBlock(stage: .line, length: length)
        }
        return RestBlock(stage: .none, length: 0)
    }

    /// The dot crossing the rail for the rest, from the log, from the row left's node to the
    /// next's.
    var restTravel: RailTravel<RoutineExercise.ID>? {
        guard let resting, let workout = session.workout else { return nil }
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
            label: rowLabel(item, current: current, on: set, bars: bars),
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

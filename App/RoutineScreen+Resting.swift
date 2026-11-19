import DesignSystem
import SwiftUI
import WorkoutStore

/// The rest between two exercises, after the last set of one, when the routine stores a rest
/// after it. One motion in, a still screen with a moving dot, one motion out: the row left closes
/// to a done row as the last set's row closes (`SetMotion.closing`), the Rest block opening under
/// it on the same curve (`RestBlock`), the key gone with its room kept; the dot travels down the
/// rail from its node to the next one's for the whole rest (`RailTravel`), the rail staying gray;
/// as the countdown reaches 0 the move goes on from its landing, as if a pulse had just landed
/// (`SetMotion.Way.afterRest`), the room closing as the next row grows. −15 s with less than
/// 15 s left ends it; +15 s moves the dot back up. There is no Skip.
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

    /// The row left closes and the rest opens under it, in the tap's own transaction.
    func startRest() {
        withTransaction(\.disablesAnimations, true) {
            isMakingRoom = true
            endFollow = nil
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

    /// The rest is over: the move to the next exercise goes on from its landing, with the tick.
    func endRest() {
        guard let rest = phase.resting, let workout = session.workout, let next = live?.currentSet,
              resting?.isOver(atClock: workout.clock(at: .now)) ?? true
        else { return }
        noteRestingPitch(of: next.row)
        let target = landing(on: next.row, leaving: rest.set.row)
        withTransaction(\.disablesAnimations, true) {
            if let target {
                growthLift = target - scrollBeat.scrolledY
                scrollPosition.scrollTo(y: target)
            }
        }
        withAnimation(SetMotion.moving(.afterRest)) {
            phase.endRest()
            growthLift = 0
        }
        land(.afterRest, scrollingTo: target)
    }

    /// −15 s or +15 s on the rest running.
    func adjustRest(by seconds: Int) {
        guard isResting, let live, let last = live.workout.sets.last, let next = live.currentSet
        else { return }
        let length = restOverride ?? routine.rest(after: last.planned, before: next)
        session.adjustRest(by: seconds, length: length)
    }

    /// The Rest block under `id`'s row, once the rest is drawn.
    func restBlock(under id: RoutineExercise.ID) -> RestBlock? {
        guard let rest = phase.resting, rest.beat >= .shown, rest.set.row == id,
              let resting, let workout = session.workout
        else { return nil }
        return RestBlock(
            ends: workout.date(ofClock: resting.endClock),
            pausedLeft: workout.isPaused
                ? resting.remaining(atClock: workout.clock(at: .now)) : nil,
            onShorten: { adjustRest(by: -15) },
            onExtend: { adjustRest(by: 15) },
        )
    }

    /// The dot traveling for the rest, from the row left's node to the next's.
    var restTravel: RailTravel<RoutineExercise.ID>? {
        guard let rest = phase.resting, rest.beat >= .shown, let resting,
              let workout = session.workout
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

    /// A row's content: its label, and under the row left, the rest, as part of the row, so the
    /// row's own stretch of rail runs through the room it opens.
    func rowContent(
        _ item: RoutineExercise,
        current: RoutineExercise.ID?,
        on set: PlannedSet?,
        bars: SetProgress?,
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            rowLabel(item, current: current, on: set, bars: bars)
            restBlock(under: item.id).map { $0.transition(.opacity) }
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

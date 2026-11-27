import DesignSystem
import SwiftUI
import WorkoutStore

/// A rest as the rows draw it (`WorkoutScreen+Resting.swift`): the block between two exercises,
/// the wait in the current exercise's figures' slot, and the time each count shows.
extension WorkoutScreen {
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
        // Skipped, its room closes with the move on showing the time it had at the tap: closed
        // as a rest that ran out is, on an empty rest, it read 0:00 as it went.
        if let move = phase.move, move.isFromRest, let live,
           let skippedAt = live.loggedWorkout.sets.last?.restSkippedAt,
           let skipped = live.rest(), skipped.after == move.set,
           let row = restRow(after: move.set, isBack: move.isBack, in: live.loggedWorkout)
        {
            // Held as a pause holds it, where the skip came in one: the time left at the tap.
            let block = RestBlock(
                stage: .none,
                length: 0,
                pausedLeft: skipped.remaining(atClock: skippedAt),
                isPaused: live.loggedWorkout.isPaused,
            )
            return DrawnRestBlock(row: row, above: move.isBack, block: block)
        }
        // Ended mid-rest, its room closes with the list showing the time it had.
        if let (rest, loggedWorkout) = phase.restLeft, !rest.isWithinExercise,
           let row = restRow(of: rest, in: loggedWorkout),
           let left = LiveWorkout(workout: workout, loggedWorkout: loggedWorkout)
               .rest()
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

    /// When `rest` ends, on `workout`'s clock running on from now, and the seconds it shows
    /// where its count stands still (`WorkoutRest.shownLeft(atClock:)`): skipped, paused, ended,
    /// or `stopped`, so the countdown holds; or where it stood at `end`, End's choice
    /// (`WorkoutPhase.drawnEnd`), as the list shrinks out of the workout End took: running on
    /// through the shrink, the count went on with a second's roll as it went.
    static func times(
        of rest: WorkoutRest,
        on loggedWorkout: LoggedWorkout,
        stopped: Bool = false,
        end: Date? = nil,
    ) -> (ends: Date, pausedLeft: Double?) {
        let holds = rest.skippedAt != nil || stopped || end != nil || loggedWorkout.isPaused
            || !loggedWorkout.isInProgress
        return (
            loggedWorkout.date(ofClock: rest.endClock),
            holds ? rest.shownLeft(atClock: loggedWorkout.clock(at: end ?? .now)) : nil,
        )
    }

    /// The rest between two sets of the current exercise, `id`, in its figures' slot: running
    /// from the log until its end, then over as it swaps back; else unseen, keeping the slot as
    /// tall as the rest for every set of an exercise that rests between them. Nil for any other
    /// row, and an exercise with no rest between its sets.
    func setRest(of id: WorkoutExercise.ID, current: WorkoutExercise.ID?) -> SetRest? {
        guard id == current, let shown,
              let gap = workout.restBetweenSets(of: id).map(LiveWorkout.running(rest:)), gap > 0
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
        return SetRest(isRunning: false, length: gap)
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

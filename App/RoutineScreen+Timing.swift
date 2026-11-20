import DesignSystem
import SwiftUI
import WorkoutStore

/// A timed set in a workout runs itself. When its turn comes with no rest before it (after
/// Start, between a set's sides, on to a superset's next member), the figures' slot shows
/// "Starts in" over a 10 s count, the set's time in words under it, and the key is "Start now";
/// as that count reaches 0 the phone taps lightly. When a rest comes first, the set's count
/// starts as the rest ends (`endRest()`). The set's count then runs in the figures' slot, with
/// no word over it and no bar under it, and the key is its log key ("Log set"), filling with the
/// done purple from its leading edge, with +15 s beside it (`TimedSetKeys`). At 0 the set logs
/// itself at its full time, with the heavy tap and the +1, and whatever follows begins: a rest,
/// or the next set's "Starts in". A tap on the log key mid-count logs the time done; +15 s adds
/// to this set only. The count runs on the workout's clock (`TimedSet`), so a pause stops it,
/// and a count that ran out while the app was away is logged at launch (`catchUp`).
extension RoutineScreen {
    /// Where the current set's count stands as drawn: read on each redraw, and redrawn as
    /// "Starts in" ends (`CountBeats.starts`).
    var countStage: CountStage? {
        _ = countBeats.starts
        return shown?.countStage(at: .now)
    }

    /// The key's fill while the set counts.
    var keyFill: KeyFill? {
        let key = liveKey
        // Once no count is drawn the count's keys are only going, in the bar's swap: they keep
        // the fill the last log left, never the next set's, which starts empty.
        let last = key.drawnCount == .counting ? nil : live.flatMap { live in
            live.workout.sets.last.flatMap { live.loggedCount(of: $0.planned) }
        }
        if let kept = key.keptCount ?? last {
            return KeyFill(length: Double(kept.length), ends: .distantPast, pausedLeft: kept.left)
        }
        guard let timed = live?.timedSet, let workout = session.workout else { return nil }
        let clock = workout.clock(at: .now)
        return KeyFill(
            length: Double(timed.length),
            ends: workout.date(ofClock: timed.endClock),
            pausedLeft: workout.isPaused ? timed.remaining(atClock: clock) : nil,
            isPaused: workout.isPaused,
        )
    }

    /// The keys while the set counts: its log key, filling, and +15 s.
    func countKeys(_ text: String, isOut: Bool) -> some View {
        TimedSetKeys(
            logText: text,
            filling: keyFill ?? KeyFill(length: 1, ends: .now),
            isOut: isOut,
            onLog: { tapKey() },
            onExtend: { perform(liveKey.countTap(by: 15)) },
        )
    }

    /// The current exercise's figures slot when its set is timed: "Starts in", or the count in
    /// the figures' place; else the rest between its sets, as `setRest(of:current:)` says, or,
    /// with none, an unseen "Starts in", so the slot keeps its room for it.
    func setWait(of id: RoutineExercise.ID, current: RoutineExercise.ID?) -> SetRest? {
        let rest = setRest(of: id, current: current)
        guard id == current, let row = routine.exercises.first(where: { $0.id == id }),
              case let .time(seconds) = row.plan.target
        else { return rest }
        let words = RestBlock.spoken(Double(seconds), locale: locale)
        // The key's count, so the slot and the key tell one story at every frame, a move out of
        // a rest included.
        let key = liveKey
        if key.drawnCount != nil, let kept = key.keptCount {
            return SetRest(
                isRunning: true,
                length: kept.length,
                pausedLeft: kept.left,
                kind: .count,
            )
        }
        guard let stage = key.drawnCount, let timed = live?.timedSet,
              let workout = session.workout
        else {
            return rest ?? SetRest(isRunning: false, length: 0, kind: .startsIn(time: words))
        }
        let clock = workout.clock(at: .now)
        let paused = workout.isPaused
        switch stage {
        case .startsIn:
            return SetRest(
                isRunning: true,
                length: LiveWorkout.startsIn,
                ends: workout.date(ofClock: timed.startClock),
                pausedLeft: paused ? timed.startsIn(atClock: clock) : nil,
                kind: .startsIn(time: RestBlock.spoken(Double(timed.length), locale: locale)),
                isPaused: paused,
            )
        case .counting:
            return SetRest(
                isRunning: true,
                length: timed.length,
                ends: workout.date(ofClock: timed.endClock),
                pausedLeft: paused ? timed.remaining(atClock: clock) : nil,
                turns: true,
                kind: .count,
                isPaused: paused,
            )
        }
    }

    /// What the count's watch waits on: a new count, "Start now", +15 s, a pause, a resume, or
    /// the screen coming to rest on the set starts it again.
    var countWatch: CountWatch? {
        guard let timed = live?.timedSet, let workout = session.workout else { return nil }
        return CountWatch(
            set: timed.set,
            startClock: timed.startClock,
            endClock: timed.endClock,
            isPaused: workout.isPaused,
            isAtRest: phase.takesLog,
        )
    }

    /// Sleeps to the end of "Starts in", taps lightly, then sleeps to the count's end and logs
    /// the set as the key would (`WorkoutKey.runOut`); never while paused, nor while the screen
    /// still shows a log. Each sleep runs on the device's clock to a point on the workout's:
    /// woken short of it, it sleeps on.
    func watchCount() async {
        guard let watch = countWatch, !watch.isPaused, watch.isAtRest else { return }
        var sleptToStart = false
        while let workout = session.workout {
            let clock = workout.clock(at: .now)
            if clock >= watch.startClock, sleptToStart {
                sleptToStart = false
                // "Starts in" swaps for the count as the figures and a rest swap.
                withAnimation(SetMotion.restSwap) { countBeats.starts += 1 }
            }
            let target = clock < watch.startClock ? watch.startClock : watch.endClock
            guard clock < target else { break }
            guard await (try? Task.sleep(for: .seconds(target - clock), tolerance: .zero)) != nil
            else { return }
            sleptToStart = sleptToStart || target == watch.startClock
        }
        perform(liveKey.runOut)
    }
}

/// The beats of a timed set the screen plays: "Starts in" reaching 0, with a light tap, and the
/// set's own end, with the heavy one and the +1.
struct CountBeats {
    var starts = 0
    var ends = 0
}

struct CountWatch: Equatable {
    let set: PlannedSet
    let startClock: Double
    let endClock: Double
    let isPaused: Bool
    let isAtRest: Bool
}

extension View {
    /// The taps a timed set plays, and its watch, on `screen`.
    func timedSets(_ screen: RoutineScreen) -> some View {
        sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: screen.countBeats.starts)
            .sensoryFeedback(.impact(weight: .heavy), trigger: screen.countBeats.ends)
            .task(id: screen.countWatch) { await screen.watchCount() }
    }
}

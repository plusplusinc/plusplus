import DesignSystem
import SwiftUI
import WorkoutStore

/// A timed set in a workout runs itself. When its turn comes with no rest before it (after
/// Start, between a set's sides, on to a superset's next member), the figures' slot shows
/// "Starts in" over a 10 s count, the set's time in words at the caption line's end, and the key
/// is "Start now": the exercise opens on it at 0:10, held, and its ten seconds start as the
/// screen comes to rest on the set (`arrivingCount()`); as that count reaches 0 the phone taps
/// lightly. When a rest comes first, the set's count starts as the rest ends (`endRest()`), or
/// at the tap that cuts it short. The set's count then runs in the figures' slot, with no word
/// over it and no bar under it, "then rest 0:30" at the caption line's end, the set's segment
/// green, and the key is "Log early", gray, filling with the done purple from its leading edge,
/// with +15 s beside it (`TimedSetKeys`). At 0 the set logs itself at its full time, with the
/// heavy tap and the +1, and whatever follows begins: a rest, or the next set's "Starts in". A
/// tap on "Log early" mid-count logs the time done, the fill running on to full and the count
/// holding where it stopped; +15 s adds to this set only. Where the set is, at rest on it, is
/// the phase's (`WorkoutPhase.timing`), which the key, the slot, the segment, and the watch
/// all read. The count runs on the workout's clock (`TimedSet`), so a pause stops it, and a
/// count that ran out while the app was away is logged at launch (`catchUp`).
extension RoutineScreen {
    /// Begins the current set's count as the screen comes to rest on it, when it is timed and
    /// has none, and says where it stands: what each transition that lands at rest is given.
    /// `lead`, the seconds the slot takes to come in from here: "Starts in" counts from then, so
    /// its 0:10 shows a full second at full strength.
    func arrivingCount(lead: Double = 0) -> CountStage? {
        session.beginCount(override: restOverride, at: .now.addingTimeInterval(lead))
        return live?.countStage(at: .now)
    }

    /// The key's fill: running while the set counts at rest or out of a rest; else full, as a
    /// set just logged holds it, early or run out, and as the count's keys leave in the bar's
    /// swap.
    var keyFill: KeyFill {
        // Ended mid-count: the fill holds where End found it as the key goes.
        if phase.endingCount == .counting, let shown, let timed = shown.timedSet {
            return KeyFill(
                length: Double(timed.length),
                ends: .distantPast,
                pausedLeft: timed.remaining(atClock: shown.workout.clock(at: .now)),
            )
        }
        guard countBeats.earlyLog == nil, phase.loggedAndDrawn == nil,
              liveKey.drawnCount == .counting,
              let timed = live?.timedSet,
              let workout = session.workout
        else { return .logged }
        let clock = workout.clock(at: .now)
        return KeyFill(
            length: Double(timed.length),
            ends: workout.date(ofClock: timed.endClock),
            pausedLeft: workout.isPaused ? timed.remaining(atClock: clock) : nil,
            isPaused: workout.isPaused,
        )
    }

    /// "Log early" tapped: the fill runs on to full from the tap as the count holds, then the
    /// log is stored at the tap's time, so a rest after it starts there, and shown, the slot and
    /// the keys changing together once the key is full.
    func logEarly(
        _ set: PlannedSet,
        of row: RoutineExercise,
        impact: WorkoutKey.Impact,
        leadingTo step: LiveWorkout.Step,
    ) {
        let tapped = Date.now
        countBeats.earlyLog = tapped
        Task {
            try? await Task.sleep(for: .seconds(PrimaryKeyButtonStyle.swapHalf), tolerance: .zero)
            guard countBeats.earlyLog == tapped else { return }
            countBeats.earlyLog = nil
            // Stored only where it shows: End, a sheet, or a stopped sequence meanwhile moved
            // the screen off rest, where a log is refused, and the store would run ahead of it.
            guard phase.isAtRest, editing == nil else { return }
            switch impact {
            case .set, .runOut: setLogs += 1
            case .side: sideLogs += 1
            }
            session.log(set, of: row, at: tapped)
            play(set, leadingTo: step)
        }
    }

    /// A timed set's caption line: it keeps room for both the set's time and what follows it,
    /// so it is as tall through "Starts in" and the count, on either side, and the figures
    /// under it never move. During "Starts in", the set's time in words, "30 seconds", stands
    /// at the line's trailing end where it fits beside the counter, else under it, as "then rest
    /// 0:30" will once it counts; the change comes in the same update as the slot's, so the line
    /// changes once, with it.
    func timedCaption(_ focus: inout RowFocus, of item: RoutineExercise) {
        guard case let .time(seconds) = item.plan.target else { return }
        focus.afterRoom = [focus.after, RestBlock.spoken(Double(seconds), locale: locale)]
            .compactMap(\.self)
        if case let .startsIn(time) = setWait(of: item.id, current: item.id)?.kind {
            focus.after = time
            focus.spokenAfter = time
            focus.showsAfter = true
        }
    }

    /// The keys while the set counts: "Log early", filling, and +15 s.
    func countKeys(_ text: String, isOut: Bool) -> some View {
        TimedSetKeys(
            logText: text,
            filling: keyFill,
            isOut: isOut,
            onLog: { tapKey() },
            // Nothing once "Log early" has stopped the set, as with a tap on the log key.
            onExtend: {
                if countBeats.earlyLog == nil {
                    perform(liveKey.countTap(by: 15))
                }
            },
        )
    }

    /// The current exercise's figures' slot when its set is timed, never its plan's figures: the
    /// rest between its sets while one runs; the count of a set just logged, where the log
    /// stopped it, in that set's own row only; at rest on the set, "Starts in" or the count as
    /// the phase says; out of a rest, the count, which the rest's end began; else, on the way
    /// to it (Start, a move), "Starts in", held at 0:10 until the screen comes to rest on it.
    func setWait(of id: RoutineExercise.ID, current: RoutineExercise.ID?) -> SetRest? {
        let rest = setRest(of: id, current: current)
        guard id == current, let shown, let row = routine.exercises.first(where: { $0.id == id }),
              case let .time(seconds) = row.plan.target
        else { return rest }
        if let within = phase.drawnRest, within.isWithinExercise, within.beat >= .shown,
           within.beat < .returning
        {
            return rest
        }
        let time = RestBlock.spoken(Double(seconds), locale: locale)
        // The workout with every log, the one drawn hidden included.
        let logs = (session.workout ?? phase.drawnWorkout).map {
            LiveWorkout(routine: routine, workout: $0)
        }
        if let logged = phase.loggedAndDrawn ?? phase.endingHidden, logged.row == id,
           let kept = logs?.loggedCount(of: logged)
        {
            return SetRest(
                isRunning: true,
                length: kept.length,
                pausedLeft: kept.left,
                kind: .count,
            )
        }
        let stage = phase.timing ?? phase.endingCount ?? (phase.isLeavingRest ? .counting : nil)
        guard let stage, let timed = shown.timedSet else {
            // On the way to the set, or ended on the way: "Starts in", held at its full count.
            return SetRest(
                isRunning: true,
                length: LiveWorkout.startsIn,
                pausedLeft: Double(LiveWorkout.startsIn),
                kind: .startsIn(time: time),
            )
        }
        let workout = shown.workout
        // Held: paused, or ended, as the workout's time holds; or logged early, where the tap
        // stopped it, as its fill runs on.
        let clock = countBeats.earlyLog.map { workout.clock(at: $0) } ?? workout.clock(at: .now)
        let holds = workout.isPaused || phase.endingCount != nil || countBeats.earlyLog != nil
        switch stage {
        case .startsIn:
            return SetRest(
                isRunning: true,
                length: LiveWorkout.startsIn,
                ends: workout.date(ofClock: timed.startClock),
                pausedLeft: holds ? timed.startsIn(atClock: clock) : nil,
                kind: .startsIn(time: RestBlock.spoken(Double(timed.length), locale: locale)),
                isPaused: workout.isPaused,
            )
        case .counting:
            return SetRest(
                isRunning: true,
                length: timed.length,
                ends: workout.date(ofClock: timed.endClock),
                pausedLeft: holds ? timed.remaining(atClock: clock) : nil,
                turns: true,
                kind: .count,
                isPaused: workout.isPaused,
            )
        }
    }

    /// What the count's watch waits on: the phase's count, a new count, "Start now", +15 s, a
    /// pause, or a resume starts it again.
    var countWatch: CountWatch? {
        guard let stage = phase.timing, let timed = live?.timedSet, let workout = session.workout
        else { return nil }
        return CountWatch(
            stage: stage,
            set: timed.set,
            startClock: timed.startClock,
            endClock: timed.endClock,
            isPaused: workout.isPaused,
        )
    }

    /// Sleeps to the end of "Starts in", then swaps it for the count with a light tap; or to the
    /// count's end, then logs the set as the key would (`WorkoutKey.runOut`). Never while
    /// paused. Each sleep runs on the device's clock to a point on the workout's: woken short of
    /// it, it sleeps on.
    func watchCount() async {
        guard let watch = countWatch, !watch.isPaused else { return }
        let target = watch.stage == .startsIn ? watch.startClock : watch.endClock
        while let workout = session.workout {
            let left = target - workout.clock(at: .now)
            guard left > 0 else { break }
            guard await (try? Task.sleep(for: .seconds(left), tolerance: .zero)) != nil
            else { return }
        }
        guard watch.stage == .startsIn else {
            // Logged early in the count's last moment: that log stands.
            guard countBeats.earlyLog == nil else { return }
            return perform(liveKey.runOut)
        }
        // "Starts in" swaps for the count as the figures and a rest swap, the key with it.
        withAnimation(SetMotion.restSwap) {
            if phase.startCount() {
                countBeats.starts += 1
            }
        }
    }
}

extension RoutineScreen {
    /// What an edit at rest can change under a count: the set current, whether it is timed, and
    /// the set the stored count is for.
    var countSubject: CountSubject {
        CountSubject(
            set: live?.currentSet,
            isTimed: live?.isOnTimedSet == true,
            counted: live?.timedSet?.set,
        )
    }

    /// An edit at rest made another set current, or changed the current set's measure: the
    /// count goes with the set it was begun for, and a timed set made current opens on "Starts
    /// in" from now, as any with no rest before it. A time changed mid-count needs nothing
    /// here: the count's length follows the row, its start kept, and its watch wakes to the new
    /// end.
    func settleCountAfterEdit() {
        guard phase.isAtRest else { return }
        session.beginCount(override: restOverride)
        withAnimation(SetMotion.restSwap) {
            phase.settleCount(on: live?.countStage(at: .now))
        }
    }
}

struct CountSubject: Equatable {
    let set: PlannedSet?
    let isTimed: Bool
    let counted: PlannedSet?
}

/// The beats of a timed set the screen plays: "Starts in" reaching 0, with a light tap, and the
/// set's own end, with the heavy one and the +1.
struct CountBeats {
    var starts = 0
    var ends = 0
    /// When "Log early" was tapped, while its fill runs on to full before the log shows.
    var earlyLog: Date?
}

struct CountWatch: Equatable {
    let stage: CountStage
    let set: PlannedSet
    let startClock: Double
    let endClock: Double
    let isPaused: Bool
}

extension WorkoutPhase {
    /// The count End came in, drawn as it stood until the workout goes.
    var endingCount: CountStage? {
        guard case let .ending(ending) = self else { return nil }
        return ending.count
    }

    /// The set logged and not yet drawn when End came, which it keeps hidden.
    var endingHidden: PlannedSet? {
        guard case let .ending(ending) = self else { return nil }
        return ending.hidden
    }
}

extension KeyFill {
    /// A set's fill once it is logged, early or run out: full, held for its beat.
    static let logged = KeyFill(length: 1, ends: .distantPast, isLogged: true)
}

extension View {
    /// The taps a timed set plays, and its watch, on `screen`.
    func timedSets(_ screen: RoutineScreen) -> some View {
        sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: screen.countBeats.starts)
            .sensoryFeedback(.impact(weight: .heavy), trigger: screen.countBeats.ends)
            .task(id: screen.countWatch) { await screen.watchCount() }
            .onChange(of: screen.countSubject) { screen.settleCountAfterEdit() }
    }
}

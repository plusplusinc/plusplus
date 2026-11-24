import DesignSystem
import SwiftUI
import WorkoutStore

/// "Start in" before a set, and a timed set running itself. As each exercise comes up (the
/// workout's first set, on to another exercise, between a superset's members in every round),
/// and before a set's other side, the figures' slot shows "Start in" over a 5 s count
/// (`Workout.startIn(before:)`); between two sets of one exercise, none. A rest before it
/// runs first, and "Start in" counts from where the rest moved on (`endRest()`), a full 5 s,
/// after a Skip rest too. With no rest before it, the exercise opens on it held at its full
/// count, and the count starts as the screen comes to rest on the set (`arrivingCount()`). It
/// reaches 0:00 and holds it a second (`LiveWorkout.startInHold`); as the hold ends and the set
/// begins, the phone taps lightly. Nothing skips it (decided 2026-11-23): through it and its hold
/// there is no key, the
/// + sitting low as with none (`WorkoutKey.waitsToStart`, decided 2026-11-24), and the set's key
/// comes in as it is up. On a reps set that is its log key, and the set's figures swap back into
/// the slot. On a timed set the set's time in words stands at the caption line's end; a timed
/// set with no "Start in" due counts from where the rest before it moved on, a quarter second
/// after a Skip rest's tap (`LiveWorkout.skipHold`). VoiceOver reads "Start in" and its time
/// left, "0 seconds" through its hold, and finds no key. The set's count then runs in the
/// figures' slot, with no word over
/// it, "then rest 0:30" at the caption line's end, the set's segment green, and the key is
/// "Log early", gray, filling with the done purple from its leading edge,
/// with +15 s beside it (`CountKeys`). At 0 the set logs itself at its full time, with the
/// heavy tap, and whatever follows begins: a rest, or the next set's "Start in". A
/// tap on "Log early" mid-count logs the time done, the fill running on to full and the count
/// holding where it stopped; +15 s adds to this set only. Finish mid-count logs the time done,
/// as "Log early" then would; Finish during a timed set's "Start in" logs nothing for the set
/// (`LiveWorkout.finishing(at:)`). Where the set is, at rest on it, is
/// the phase's (`WorkoutPhase.timing`), which the key, the slot, the segment, and the watch
/// all read. The count runs on the workout's clock (`TimedSet`), so a pause stops it, and a
/// count that ran out while the app was away is logged at launch (`catchUp`).
extension WorkoutScreen {
    /// Begins the current set's count as the screen comes to rest on it, when it is timed and
    /// has none, and says where it stands: what each transition that lands at rest is given.
    /// `lead`, the seconds the slot takes to come in from here: "Start in" counts from then, so
    /// its 0:05 shows a full second at full strength.
    func arrivingCount(lead: Double = 0) -> CountStage? {
        session.beginCount(override: restOverride, at: .now.addingTimeInterval(lead))
        return live?.countStage(at: .now)
    }

    /// As `arrivingCount()`, for Start's landing on the first set: the workout's time holds at
    /// 0:00 through its "Start in" and starts as the set begins, so the two tick together.
    func startingCount() -> CountStage? {
        session.landOnFirstSet(override: restOverride)
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
                pausedLeft: timed
                    .remaining(atClock: shown.loggedWorkout.clock(at: phase.drawnMoment)),
            )
        }
        guard countBeats.earlyLog == nil, phase.loggedAndDrawn == nil,
              liveKey.drawnCount == .counting,
              let timed = live?.timedSet,
              let loggedWorkout = session.loggedWorkout
        else { return .over }
        let clock = loggedWorkout.clock(at: .now)
        return KeyFill(
            length: Double(timed.length),
            ends: loggedWorkout.date(ofClock: timed.endClock),
            pausedLeft: loggedWorkout.isPaused ? timed.remaining(atClock: clock) : nil,
            isPaused: loggedWorkout.isPaused,
        )
    }

    /// "Log early" tapped: the phone's tap plays at once, and the fill runs on to full from the
    /// tap as the count holds, then the log is stored at the tap's time, so a rest after it
    /// starts there, and shown, the slot and the keys changing together once the key is full.
    /// A sheet opened while the key fills leaves the set counting, its tap already played.
    func logEarly(
        _ set: PlannedSet,
        of row: WorkoutExercise,
        impact: WorkoutKey.Impact,
        leadingTo step: LiveWorkout.Step,
    ) {
        let tapped = Date.now
        countBeats.earlyLog = tapped
        // The tap's own answer: waiting for the fill, the phone's tap came late.
        switch impact {
        case .set, .runOut: setLogs += 1
        case .side: sideLogs += 1
        }
        Task {
            try? await Task.sleep(for: .seconds(PrimaryKeyButtonStyle.swapHalf), tolerance: .zero)
            guard countBeats.earlyLog == tapped else { return }
            countBeats.earlyLog = nil
            // Stored only where the log shows: End, a sheet, or a stopped sequence meanwhile moved
            // the screen off rest, where a log is refused, and the store would run ahead of it.
            guard phase.isAtRest, editing == nil else { return }
            session.log(set, of: row, at: tapped)
            play(set, leadingTo: step)
        }
    }

    /// A timed set's caption line: it keeps room for both the set's time and what follows it,
    /// so it is as tall through "Start in" and the count, on either side, and the figures
    /// under it never move. During "Start in", the set's time in words, "30 seconds", stands
    /// at the line's trailing end where it fits beside the counter, else under it, as "then rest
    /// 0:30" will once it counts; the change comes in the same update as the slot's, so the line
    /// changes once, with it.
    func timedCaption(_ focus: inout RowFocus, of item: WorkoutExercise) {
        guard case let .time(seconds) = item.plan.target else { return }
        focus.afterRoom = [focus.after, RestBlock.spoken(Double(seconds), locale: locale)]
            .compactMap(\.self)
        if case let .startIn(time?) = setWait(of: item.id, current: item.id)?.kind {
            focus.after = time
            focus.spokenAfter = time
            focus.showsAfter = true
        }
    }

    /// The keys while the set counts: "Log early", filling, and +15 s.
    func countKeys(_ text: String, isOut: Bool) -> some View {
        CountKeys(
            text: text,
            filling: keyFill,
            isOut: isOut,
            onKey: { tapKey() },
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
    /// stopped it, in that set's own row only; at rest on the set, "Start in" or the count as
    /// the phase says; out of a rest, "Start in" or the count, which the rest's end began; else,
    /// on the way to it (Start, a move), "Start in", held at its full count until the screen
    /// comes to rest on it. On a reps set, its "Start in" the same way, else the rest or its
    /// figures.
    func setWait(of id: WorkoutExercise.ID, current: WorkoutExercise.ID?) -> SetRest? {
        let rest = setRest(of: id, current: current)
        guard id == current, let shown, let row = workout.exercises.first(where: { $0.id == id })
        else { return rest }
        if let within = phase.drawnRest, within.isWithinExercise, within.beat >= .shown,
           within.beat < .returning
        {
            return rest
        }
        guard case let .time(seconds) = row.plan.target else {
            return repsStartIn(of: row, in: shown) ?? rest
        }
        let time = RestBlock.spoken(Double(seconds), locale: locale)
        // The workout with every log, the one drawn hidden included.
        let logs = (session.loggedWorkout ?? phase.drawnLoggedWorkout).map {
            LiveWorkout(workout: workout, loggedWorkout: $0)
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
        let length = shown.startInLength
        guard let stage = drawnStage(in: shown), let timed = shown.timedSet else {
            // On the way to the set, or ended on the way: "Start in", held at its full count.
            return SetRest(
                isRunning: true,
                length: length,
                pausedLeft: Double(length),
                kind: .startIn(time: time),
            )
        }
        let loggedWorkout = shown.loggedWorkout
        // Held: paused; or ended, where End found it (`drawnMoment`), as the workout's time
        // holds; or logged early, where the tap stopped it, as its fill runs on.
        let clock = loggedWorkout.clock(at: countBeats.earlyLog ?? phase.drawnMoment)
        let holds = loggedWorkout.isPaused || phase.endingCount != nil || countBeats.earlyLog != nil
        switch stage {
        case .startIn:
            return SetRest(
                isRunning: true,
                length: length,
                // Reading 0:00 for its hold before the set begins.
                ends: loggedWorkout.date(ofClock: timed.startClock - LiveWorkout.startInHold),
                pausedLeft: holds
                    ? max(0, timed.startIn(atClock: clock) - LiveWorkout.startInHold) : nil,
                turns: true,
                kind: .startIn(time: RestBlock.spoken(Double(timed.length), locale: locale)),
                isPaused: loggedWorkout.isPaused,
            )
        case .counting:
            return SetRest(
                isRunning: true,
                length: timed.length,
                ends: loggedWorkout.date(ofClock: timed.endClock),
                pausedLeft: holds ? timed.remaining(atClock: clock) : nil,
                turns: true,
                kind: .count,
                isPaused: loggedWorkout.isPaused,
            )
        }
    }

    /// Where the current set's count stands as drawn: the phase's at rest on it, End's as it
    /// found it, and out of a rest, the stored count's, which the rest's end began.
    private func drawnStage(in shown: LiveWorkout) -> CountStage? {
        phase.drawnCount
            ?? (phase.isLeavingRest ? shown.countStage(at: .now) ?? .counting : nil)
    }

    /// A reps set's "Start in" in the figures' slot, as a timed set's: running at rest on it or
    /// out of a rest; held at its full count on the way to it (Start, a move) where one is due;
    /// else nil, and the set's figures stand.
    private func repsStartIn(of row: WorkoutExercise, in shown: LiveWorkout) -> SetRest? {
        guard case .reps = row.plan.target, let set = shown.currentSet,
              set.row == row.id, phase.loggedAndDrawn == nil
        else { return nil }
        let length = shown.startInLength
        guard drawnStage(in: shown) == .startIn, let count = shown.setCount else {
            // Through all of Start, the beat between the landing and the key coming up, and the
            // crossfade with no motion, included: without them the set's figures showed for that
            // beat, then "Start in" came back.
            guard phase.isOnWayIn || phase.isMovingOn, shown.workout.startIn(before: set) > 0
            else { return nil }
            return SetRest(
                isRunning: true,
                length: length,
                pausedLeft: Double(length),
                kind: .startIn(),
            )
        }
        let loggedWorkout = shown.loggedWorkout
        let holds = loggedWorkout.isPaused || phase.endingCount != nil
        // Reading 0:00 for its hold before the set begins.
        let zero = count.startClock - LiveWorkout.startInHold
        return SetRest(
            isRunning: true,
            length: length,
            ends: loggedWorkout.date(ofClock: zero),
            pausedLeft: holds ? max(0, zero - loggedWorkout.clock(at: phase.drawnMoment)) : nil,
            turns: true,
            kind: .startIn(),
            isPaused: loggedWorkout.isPaused,
        )
    }

    /// What the count's watch waits on: the phase's count, a new count, +15 s, a
    /// pause, or a resume starts it again. On a reps set, its "Start in" alone.
    var countWatch: CountWatch? {
        guard let stage = phase.timing, let live, let count = live.setCount,
              let loggedWorkout = session.loggedWorkout
        else { return nil }
        return CountWatch(
            stage: stage,
            set: count.set,
            startClock: count.startClock,
            endClock: live.timedSet?.endClock ?? count.startClock,
            isPaused: loggedWorkout.isPaused,
        )
    }

    /// Sleeps to the end of "Start in", then swaps it for a timed set's count, or a reps set's
    /// figures, with a light tap; or to a timed set's end, then logs the set as the key would
    /// (`WorkoutKey.runOut`). Never while paused. Each sleep runs on the device's clock to a
    /// point on the workout's: woken short of it, it sleeps on.
    func watchCount() async {
        guard let watch = countWatch, !watch.isPaused else { return }
        let target = watch.stage == .startIn ? watch.startClock : watch.endClock
        while let loggedWorkout = session.loggedWorkout {
            let left = target - loggedWorkout.clock(at: .now)
            guard left > 0 else { break }
            guard await (try? Task.sleep(for: .seconds(left), tolerance: .zero)) != nil
            else { return }
        }
        guard watch.stage == .startIn else {
            // Logged early in the count's last moment: that log stands.
            guard countBeats.earlyLog == nil else { return }
            return perform(liveKey.runOut)
        }
        // "Start in" swaps for the count as the figures and a rest swap, the key with it.
        withAnimation(SetMotion.restSwap) {
            if phase.startCount(isTimed: live?.isOnTimedSet ?? true) {
                countBeats.starts += 1
            }
        }
    }
}

extension WorkoutScreen {
    /// What an edit at rest can change under a count: the set current, whether it is timed, and
    /// the set the stored count is for.
    var countSubject: CountSubject {
        CountSubject(
            set: live?.currentSet,
            isTimed: live?.isOnTimedSet == true,
            counted: live?.setCount?.set,
        )
    }

    /// An edit at rest made another set current, or changed the current set's measure: the
    /// count goes with the set it was begun for, or, for a measure changed, as the edit was
    /// saved (`AppSession.save(_:)`), and a set made current, or changed to reps or to a time,
    /// opens on the "Start in" due before it from now, a timed one on "Start in" in any case, as
    /// any with no rest before it. A time changed mid-count needs nothing here: the count's
    /// length follows the row, its start kept, and its watch wakes to the new end.
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

/// The beats of a set the screen plays: "Start in" reaching 0, with a light tap, and the
/// set's own end, with the heavy one.
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
    /// The set logged and not yet drawn when End came, which it keeps hidden.
    var endingHidden: PlannedSet? {
        guard case let .ending(ending) = self else { return nil }
        return ending.hidden
    }
}

extension View {
    /// The taps a timed set plays, and its watch, on `screen`.
    func timedSets(_ screen: WorkoutScreen) -> some View {
        sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: screen.countBeats.starts)
            .sensoryFeedback(.impact(weight: .heavy), trigger: screen.countBeats.ends)
            .task(id: screen.countWatch) { await screen.watchCount() }
            .onChange(of: screen.countSubject) { screen.settleCountAfterEdit() }
    }
}

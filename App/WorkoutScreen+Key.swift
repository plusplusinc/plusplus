import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen's one key, at the bottom: Start, then in a workout what logs its sets, goes back
/// to the current exercise while it is scrolled away, and finishes the workout.
extension WorkoutScreen {
    /// The key as the workout stands: what it says, which the bar swaps as its kind changes
    /// (`primaryKeyBar`), and what a tap does.
    var liveKey: WorkoutKey {
        WorkoutKey(
            stored: live,
            shown: shown,
            phase: phase,
            wayBack: keyWayBack,
            isScrolledAway: currentPlace?.isScrolledAway == true,
        )
    }

    /// The key that `primaryKeyBar` holds, for `role`. Within a kind, one key whose words
    /// change; across kinds, another key, which the bar swaps in. While the bar has it out in a
    /// swap, a tap or a VoiceOver activation does nothing, and the key stays enabled, so
    /// VoiceOver doesn't read it dimmed for the swap's length. During a rest the bar swaps it for
    /// Skip rest, filling as the rest runs, and +15 s (`CountKeys`), and back as the rest ends.
    @ViewBuilder
    func key(_ role: WorkoutKey.Role, isOut: Bool) -> some View {
        if role == .rest {
            CountKeys(
                text: spokenKey(role),
                filling: restKeyFill,
                spoken: .left,
                isOut: isOut,
                onKey: { perform(liveKey.skipRest) },
                onExtend: { perform(liveKey.extendRest(by: 15)) },
            )
        } else if case let .count(text) = role {
            countKeys(text, isOut: isOut)
        } else {
            mainKey(role, isOut: isOut)
        }
    }

    private func mainKey(_ role: WorkoutKey.Role, isOut: Bool) -> some View {
        Button {
            if !isOut {
                tapKey()
            }
        } label: { keyLabel(role) }
            .accessibilityLabel(spokenKey(role))
            // Not on Start, which the tests find by its label.
            .accessibilityIdentifier(role == .start ? "" : "workout.key")
    }

    @ViewBuilder
    private func keyLabel(_ role: WorkoutKey.Role) -> some View {
        switch role {
        case .start:
            Label("Start", systemImage: "play.fill")
        case let .back(exercise, isAbove):
            // Whole, wrapping at the largest text sizes rather than cut short.
            Label(exercise, systemImage: isAbove ? "arrow.up" : "arrow.down")
        case .log, .finish, .rest, .count:
            // One branch, so words that stay are the same view: a branch per role crossfaded
            // "Log last set" into itself as the last set's row closed, which dimmed it.
            Text(verbatim: spokenKey(role))
        }
    }

    private func spokenKey(_ role: WorkoutKey.Role) -> String {
        switch role {
        case .start: String(localized: "Start")
        case let .log(text), let .count(text): text
        case let .back(exercise, _): String(localized: "Go to current exercise, \(exercise)")
        case .finish: String(localized: "Finish workout")
        case .rest: String(localized: "Skip rest")
        }
    }

    /// A tap on the key, as `WorkoutKey.tap` says. Nothing while a row's sheet is up: it covers
    /// the key, but a tap as it began to rise, as after Create, reached the key and started or
    /// logged behind it. While the key swaps, `key` drops the tap.
    func tapKey() {
        guard editing == nil else { return }
        // Nothing more once "Log early" has stopped the set.
        guard countBeats.earlyLog == nil else { return }
        perform(liveKey.tap)
    }

    /// +15 s on the rest running: the key's fill steps back at once and the countdown turns; the
    /// dot stays put. Only when `WorkoutKey.extendRest(by:)` says so.
    private func extendRest(by seconds: Int) {
        withAnimation(SetMotion.restRoll) {
            session.extendRest(by: seconds, override: restOverride)
        }
    }

    /// Skip rest: the rest is stored as cut at the tap (`LiveWorkout.skippingRest(override:at:)`),
    /// its count holding the time it had left at the tap for a second, then ending as one that
    /// ran out does, as the rest's watch says (`watchRest()`). Its keys go at the tap. Only when
    /// `WorkoutKey.skipRest` says so.
    private func skipRest() {
        // With the store's change, before `endRest()`'s animated swap: a new figure put in during
        // the swap stood where it ends from its first frame.
        restSkips += 1
        if let resting, let loggedWorkout = session.loggedWorkout,
           let left = Self.times(of: resting, on: loggedWorkout, stopped: true).pausedLeft
        {
            phase.skipRest(left: left)
            skipLeave = loggedWorkout.clock(at: .now) + LiveWorkout.restHold
        }
        session.skipRest(override: restOverride)
    }

    /// Whether the + sits low, at the screen's bottom, with no key under it: with no exercises,
    /// and in a workout wherever the key's room is kept empty, so it never floats over a key
    /// that isn't there (decided 2026-11-24). It goes down and comes back up on the update that
    /// takes the key away or brings it in (`FloatingPlace`).
    var plusSitsLow: Bool {
        footShowsEmpty || (keyKeepsRoom && !showsKey)
    }

    /// The fill of Skip rest: running while the rest runs, gray and held while paused; held where
    /// it stood where End came mid-rest; else full, as the keys leave once the rest is over.
    var restKeyFill: KeyFill {
        if let (_, loggedWorkout) = phase.restLeft,
           let left = LiveWorkout(workout: workout, loggedWorkout: loggedWorkout)
               .rest(override: restOverride)
        {
            let (ends, pausedLeft) = Self.times(of: left, on: loggedWorkout, stopped: true)
            return KeyFill(length: Double(left.length), ends: ends, pausedLeft: pausedLeft)
        }
        guard let rest = phase.drawnRest, rest.beat < .returning,
              let (resting, loggedWorkout) = drawnResting,
              resting.remaining(atClock: loggedWorkout.clock(at: .now)) > 0
        else { return .over }
        let (ends, pausedLeft) = Self.times(of: resting, on: loggedWorkout, end: phase.drawnEnd)
        return KeyFill(
            length: Double(resting.length),
            ends: ends,
            pausedLeft: pausedLeft,
            isPaused: loggedWorkout.isPaused,
        )
    }

    /// What a tap on the key, or on Skip rest or +15 s, does. A log is stored through the session
    /// at once and shown through `play(_:leadingTo:)`.
    func perform(_ tap: WorkoutKey.Tap) {
        switch tap {
        case .start:
            pressStart()
        case .finish:
            finish()
        case .back:
            // With Reduce Motion the list jumps back, as the key's swap only fades.
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.4), scrollToCurrent)
        case let .log(set, current, impact, step):
            log(set, of: current, impact: impact, leadingTo: step)
        case .skipRest:
            skipRest()
        case let .extendRest(seconds):
            extendRest(by: seconds)
        case let .extendCount(seconds):
            session.extendCount(by: seconds)
        case .nothing:
            break
        }
    }

    private func log(
        _ set: PlannedSet,
        of current: WorkoutExercise,
        impact: WorkoutKey.Impact,
        leadingTo step: LiveWorkout.Step,
    ) {
        if impact != .runOut, phase.timing == .counting {
            return logEarly(set, of: current, impact: impact, leadingTo: step)
        }
        switch impact {
        case .set: setLogs += 1
        case .side: sideLogs += 1
        case .runOut: countBeats.ends += 1
        }
        // Stored at once, at the numbers the row shows; then shown, from the workout before it.
        session.log(set, of: current)
        play(set, leadingTo: step)
    }

    /// Settles which way the key points: back to the current exercise while it is scrolled away,
    /// out of view, else none, which the bar swaps the key for. Called as the row crosses that
    /// line, as the scroll phase changes, and as a move lands. Held while a finger is on the list,
    /// so the key doesn't change under a thumb about to tap it; once the finger lifts, it follows
    /// the row as the list coasts, swapping as the row crosses the line rather than once the list
    /// stops (about 0.95 s after a flick, with the swap's 0.45 s after that, the key lagged the
    /// list). Not while moving
    /// on, whose row passes through the edge, nor before a relaunch has opened on the current
    /// exercise. Nor while the list rubber-bands past its top: a flick back to the top pulled
    /// the current exercise mostly below the screen for a moment, and the key went from back
    /// up, to Log set, to back down, to Log set within 0.2 s. Past the end, the rows only go
    /// further the way they were going.
    func settleWayBack() {
        guard !isMovingOn, !opensOnCurrent, !scrollBeat.isFingerOn, !scrollBeat.isPastTop else {
            return
        }
        let way: WorkoutKey.WayBack? = if let place = currentPlace, place.isScrolledAway,
                                          currentID != nil
        {
            place.isAbove ? .up : .down
        } else {
            nil
        }
        guard way != keyWayBack else { return }
        keyWayBack = way
    }

    /// After a log that stays on the exercise, the beat the set is held for before the line
    /// rolls on, timed from the log. On the screen's sequence, so the screen going away stops it
    /// and shows the set at once (`stopSequence()`).
    func rollHeldSet() {
        sequence.run {
            let start = ContinuousClock.now
            try await beat(until: start + .seconds(SetMotion.heldRoll))
            withAnimation(.snappy(duration: SetMotion.roll)) {
                phase.rollOn(on: arrivingCount(lead: SetMotion.roll))
            }
        }
    }
}

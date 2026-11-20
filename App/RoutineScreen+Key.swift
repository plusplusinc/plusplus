import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen's one key, at the bottom: Start, then in a workout what logs its sets, goes back
/// to the current exercise while it is scrolled away, and finishes the workout.
extension RoutineScreen {
    typealias KeyRole = WorkoutKey.Role

    /// The key as the workout stands: what it says and what a tap does, both worked out by
    /// `WorkoutKey`.
    var liveKey: WorkoutKey {
        WorkoutKey(
            stored: live,
            shown: shown,
            phase: phase,
            wayBack: keyWayBack.map { $0 == .top ? .up : .down },
            isScrolledAway: currentPlace?.isScrolledAway == true,
        )
    }

    /// What the key is for, as the workout stands. The bar swaps the key as its kind changes
    /// (`primaryKeyBar`).
    var liveKeyRole: KeyRole {
        liveKey.role
    }

    /// The key that `primaryKeyBar` holds, for `role`. Within a kind, one key whose words
    /// change; across kinds, another key, which the bar swaps in. While the bar has it out in a
    /// swap, a tap or a VoiceOver activation does nothing, and the key stays enabled, so
    /// VoiceOver doesn't read it dimmed for the swap's length.
    func key(_ role: KeyRole, isOut: Bool) -> some View {
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
    private func keyLabel(_ role: KeyRole) -> some View {
        switch role {
        case .start:
            Label("Start", systemImage: "play.fill")
        case let .back(exercise, isAbove):
            // Whole, wrapping at the largest text sizes rather than cut short.
            Label(exercise, systemImage: isAbove ? "arrow.up" : "arrow.down")
        case .log, .finish:
            // One branch, so words that stay are the same view: a branch per role crossfaded
            // "Log last set" into itself as the last set's row closed, which dimmed it.
            Text(verbatim: spokenKey(role))
        }
    }

    private func spokenKey(_ role: KeyRole) -> String {
        switch role {
        case .start: String(localized: "Start")
        case let .log(text): text
        case let .back(exercise, _): String(localized: "Go to current exercise, \(exercise)")
        case .finish: String(localized: "Finish workout")
        }
    }

    /// A tap on the key, as `WorkoutKey.tap` says. Where the current exercise is scrolled away
    /// when the tap lands, as on a list still moving away under a finger that still says "Log
    /// set", the list goes back to it and nothing is logged: the key changes only once the finger
    /// lifts (`settleWayBack()`), the place at once. A log is stored through the session at once
    /// and shown through `play(_:leadingTo:)`. Nothing while a row's sheet is up: it covers the
    /// key, but a tap as it began to rise, as after Create, reached the key and started or logged
    /// behind it. While the key swaps, `key` drops the tap.
    func tapKey() {
        guard editing == nil else { return }
        switch liveKey.tap {
        case .start:
            pressStart()
        case .finish:
            finish()
        case .back:
            // With Reduce Motion the list jumps back, as the key's swap only fades.
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.4), scrollToCurrent)
        case let .log(set, current, impact, step):
            switch impact {
            case .set: setLogs += 1
            case .side: sideLogs += 1
            }
            // Stored at once, at the numbers the row shows; then shown, from the workout before
            // it.
            session.log(set, of: current)
            play(set, leadingTo: step)
        case .nothing:
            break
        }
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
        let way: VerticalEdge? = if let place = currentPlace, place.isScrolledAway,
                                    currentID != nil
        {
            place.isAbove ? .top : .bottom
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
            withAnimation(.snappy(duration: SetMotion.roll)) { phase.show() }
        }
    }
}

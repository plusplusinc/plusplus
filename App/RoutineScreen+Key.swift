import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen's one key, at the bottom: Start, then in a workout what logs its sets, goes back
/// to the current exercise while it is scrolled away, and finishes the workout.
extension RoutineScreen {
    /// What the key is for now.
    enum KeyRole: Equatable {
        case start
        /// Logs the current set, saying which ("Log set", "Log left", "Log last set").
        case log(String)
        /// The current exercise is scrolled away, above it or not: the key goes back to it.
        case back(name: String, isAbove: Bool)
        /// After the last set, as its row closes: it still says so, and takes no tap.
        case closing
        case finish

        /// Which key this is: a change of kind swaps the key for another, a change within one,
        /// as "Log left" to "Log right", changes its words. Closing is the log key still, which
        /// says "Log last set" until Finish workout takes its place.
        enum Kind: Hashable {
            case start
            case log
            case back
            case finish
        }

        var kind: Kind {
            switch self {
            case .start: .start
            case .log, .closing: .log
            case .back: .back
            case .finish: .finish
            }
        }
    }

    /// What the key shows: while it swaps, the role it had, until it has gone.
    var keyRole: KeyRole {
        heldKeyRole ?? liveKeyRole
    }

    /// What the key is for, as the workout stands.
    private var liveKeyRole: KeyRole {
        guard let workout = session.workout, !isStarting else { return .start }
        if isWorkoutDone {
            return isMovingOn ? .closing : .finish
        }
        if let way = keyWayBack, let current = currentExercise {
            return .back(name: current.exercise.name, isAbove: way == .top)
        }
        // The held set until the line rolls on, so the key changes with the row, not before it.
        guard let set = heldSet ?? currentSet else { return .finish }
        return .log(routine.logText(for: set, after: shownSets ?? workout.sets))
    }

    /// The key that `primaryKeyBar` holds, for `role`. Within a kind, one key whose words
    /// change; across kinds, another key (`swapKey(_:)`).
    func key(_ role: KeyRole, named name: String) -> some View {
        Button { tapKey(named: name) } label: { keyLabel(role) }
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
        case .log, .closing, .finish:
            // One branch, so the words that stay as the last set closes ("Log last set") are
            // the same view: a branch of its own crossfaded the text into itself, which
            // dimmed it for the closing's 0.65 s.
            Text(verbatim: spokenKey(role))
        }
    }

    private func spokenKey(_ role: KeyRole) -> String {
        switch role {
        case .start: String(localized: "Start")
        case let .log(text): text
        case let .back(exercise, _): String(localized: "Go to current exercise, \(exercise)")
        case .closing: String(localized: "Log last set")
        case .finish: String(localized: "Finish workout")
        }
    }

    /// A tap on the key. Out of a workout, Start. After the last set, Finish workout. Otherwise,
    /// where the current exercise is mostly out of view when the tap lands, as on a list still
    /// moving away under a finger that still says "Log set", the list goes back to it and nothing
    /// is logged: the key changes only once the finger lifts (`settleKeyRole()`), the place at
    /// once.
    func tapKey(named name: String) {
        guard session.workout != nil, !isStarting else { return pressStart() }
        guard !isMovingOn, !isKeySwapping else { return }
        if isWorkoutDone {
            return finish(named: name)
        }
        guard let current = currentExercise, let set = currentSet else { return }
        if keyWayBack != nil || currentPlace?.isMostlyOut == true {
            withAnimation(.snappy(duration: 0.4), scrollToCurrent)
            return
        }
        // A second tap while the set just logged is held, as a double tap would be, is dropped.
        guard heldSet == nil else { return }
        plusOnes += 1
        if set.side == nil {
            setLogs += 1
        } else {
            sideLogs += 1
        }
        log(set, of: current)
    }

    /// Settles which way the key points: back to the current exercise while it is mostly out of
    /// view, else none. Called as the row crosses that line, as the scroll phase changes, and
    /// as a move lands. Held while a finger is on the list, so the key doesn't change under a
    /// thumb about to tap it; once the finger lifts, it follows the row as the list coasts,
    /// swapping as the row crosses the line rather than once the list stops (about 0.95 s after
    /// a flick, with the swap's 0.45 s after that, the key lagged the list). Not while moving
    /// on, whose row passes through the edge, nor before a relaunch has opened on the current
    /// exercise. Nor while the list rubber-bands past its top: a flick back to the top pulled
    /// the current exercise mostly below the screen for a moment, and the key went from back
    /// up, to Log set, to back down, to Log set within 0.2 s. Past the end, the rows only go
    /// further the way they were going.
    func settleKeyRole() {
        guard !isMovingOn, !opensOnCurrent, !scrollBeat.isFingerOn, !scrollBeat.isPastTop else {
            return
        }
        let way: VerticalEdge? = if currentID != nil, let place = currentPlace, place.isMostlyOut {
            place.isAbove ? .top : .bottom
        } else {
            nil
        }
        guard way != keyWayBack else { return }
        swapKey { keyWayBack = way }
    }

    /// Makes `change`, and where it changes the key's kind, swaps the key: the one showing goes
    /// down out of the screen's bottom edge with its words as they were, then the new one comes
    /// up in from it, one after the other, never two keys at once and never both words on one
    /// (with Reduce Motion, each fades). The bar keeps its room throughout, so the list under it
    /// stays put: with the bar gone between them, a list at its end moved down, which changed
    /// whether the current exercise was in view, and the key back with it. A tap while it swaps does nothing. Within a kind, the
    /// words change in place. During a swap, `change` is made at once and the key coming in
    /// shows the workout as it stands then.
    func swapKey(_ change: () -> Void) {
        guard !isKeySwapping else { return change() }
        let shown = keyRole
        heldKeyRole = shown
        change()
        guard liveKeyRole.kind != shown.kind else {
            heldKeyRole = nil
            return
        }
        // Easing in, so it is still in sight until it clears the edge, and the next one comes up
        // straight after: easing out, it crept out of sight over its last frames.
        withAnimation(.easeIn(duration: Self.keySwap)) { isKeySwapping = true }
        Task {
            try? await Task.sleep(for: .seconds(Self.keySwap), tolerance: .zero)
            // Out of sight, the key becomes the next one with no transition of its own.
            withTransaction(\.disablesAnimations, true) { heldKeyRole = nil }
            // On a later turn of the run loop, from out of sight, as `bringKeyBack()`.
            Task {
                withAnimation(.smooth(duration: Self.keySwap)) { isKeySwapping = false }
            }
        }
    }

    /// Each half of a key swap: the key going down and out, then the next coming up and in on
    /// Start's own curve, as Start comes back after End.
    static let keySwap = startReturn

    /// After a log that stays on the exercise, the beat the set is held for before the line
    /// rolls on. A task on the held set, so the screen going away cancels it.
    func rollHeldSet() async {
        guard unshownSet != nil else { return }
        do {
            try await Task.sleep(for: .seconds(SetMotion.heldRoll), tolerance: .zero)
        } catch {
            return
        }
        withAnimation(.snappy(duration: SetMotion.roll)) { unshownSet = nil }
    }
}

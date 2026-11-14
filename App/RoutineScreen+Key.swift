import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen's one key, at the bottom: Start, then in a workout what logs its sets, goes back
/// to the current exercise while it is scrolled away, and finishes the workout.
extension RoutineScreen {
    /// What the key is for now.
    enum KeyRole: Equatable, Identifiable {
        case start
        /// Logs the current set, saying which ("Log set", "Log left", "Log last set"). After the
        /// last set, as its row closes, it still says "Log last set", and takes no tap.
        case log(String)
        /// The current exercise is scrolled away, above it or not: the key goes back to it.
        case back(name: String, isAbove: Bool)
        case finish

        /// Which key this is: a change of kind swaps the key for another, a change within one,
        /// as "Log left" to "Log right", changes its words.
        enum Kind: Hashable {
            case start
            case log
            case back
            case finish
        }

        var kind: Kind {
            switch self {
            case .start: .start
            case .log: .log
            case .back: .back
            case .finish: .finish
            }
        }

        /// The key's identity in its bar, which swaps it for another as it changes.
        var id: Kind {
            kind
        }
    }

    /// How the key is away from its bar.
    enum KeyAway {
        /// At Start, from the grow's end until the workout's key comes up: its room in the bar
        /// stays, so the list's bottom inset doesn't change as Start goes and the next key comes.
        case keepingRoom
        /// At a workout's end, or Start's crossfade with Reduce Motion: its room goes with it.
        case givingUpRoom
    }

    /// What the key is for, as the workout stands. The bar swaps the key as its kind changes
    /// (`primaryKeyBar`).
    var liveKeyRole: KeyRole {
        guard let shown, !isStarting else { return .start }
        // While the workout moves on from a set, the key is still that set's until the next row
        // shows its own, so it changes with the row: read from the workout, it said the next
        // exercise's set ("Log left") as the pulse set off. After the last set, through the close.
        if isMovingOn, exerciseMove?.hasRolled != true, let set = playback.playing?.set,
           let text = live?.hiding(playback.unshown + [set]).logText
        {
            return .log(text)
        }
        if shown.isDone {
            return .finish
        }
        if let way = keyWayBack, let current = shown.currentExercise {
            return .back(name: current.exercise.name, isAbove: way == .top)
        }
        // As drawn, the held set until the line rolls on, so the key changes with the row, not
        // before it.
        return shown.logText.map(KeyRole.log) ?? .finish
    }

    /// The key that `primaryKeyBar` holds, for `role`. Within a kind, one key whose words
    /// change; across kinds, another key, which the bar swaps in.
    func key(_ role: KeyRole) -> some View {
        Button { tapKey() } label: { keyLabel(role) }
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

    /// A tap on the key. Out of a workout, Start. After the last set, Finish workout. Otherwise,
    /// where the current exercise is scrolled away when the tap lands, as on a list still
    /// moving away under a finger that still says "Log set", the list goes back to it and nothing
    /// is logged: the key changes only once the finger lifts (`settleWayBack()`), the place at
    /// once. A log is stored through the session at once and shown through `play(_:)`.
    func tapKey() {
        guard let live, !isStarting else { return pressStart() }
        // Nothing while the workout moves on to the next exercise; while the key swaps, the bar
        // takes no tap (`primaryKeyBar`).
        guard !isMovingOn else { return }
        if live.isDone {
            return finish()
        }
        guard let current = live.currentExercise, let set = live.currentSet else { return }
        if keyWayBack != nil || currentPlace?.isScrolledAway == true {
            // With Reduce Motion the list jumps back, as the key's swap only fades.
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.4), scrollToCurrent)
            return
        }
        // A second tap while the set just logged is held, as a double tap would be, is dropped;
        // a move already returned above.
        guard playback.takesLog else { return }
        if set.side == nil {
            setLogs += 1
        } else {
            sideLogs += 1
        }
        // Stored at once, at the numbers the row shows; then shown. The guards above take a log
        // only with no step playing, so today its step starts now.
        session.log(set, of: current)
        if playback.log(set) {
            play(set)
        }
    }

    /// Settles which way the key points: back to the current exercise while it is scrolled away,
    /// out of view, else none, which the bar swaps the key for. Called as the row crosses that
    /// line, as the scroll phase changes, and as a move lands. Held while a finger is on the list,
    /// so the key doesn't change under a
    /// thumb about to tap it; once the finger lifts, it follows the row as the list coasts,
    /// swapping as the row crosses the line rather than once the list stops (about 0.95 s after
    /// a flick, with the swap's 0.45 s after that, the key lagged the list). Not while moving
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
        keyWayBack = way
    }

    /// After a log that stays on the exercise, the beat the set is held for before the line
    /// rolls on. A task on the held set, so the screen going away cancels it; cancelled, the set
    /// shows at once, so the step still ends and the next log plays.
    func rollHeldSet() async {
        guard playback.held != nil else { return }
        let rolls: Bool
        do {
            try await Task.sleep(for: .seconds(SetMotion.heldRoll), tolerance: .zero)
            rolls = true
        } catch {
            rolls = false
        }
        withAnimation(rolls ? .snappy(duration: SetMotion.roll) : nil) { playback.show() }
        endStep()
    }
}

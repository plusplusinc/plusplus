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
    }

    var keyRole: KeyRole {
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

    /// The key that `primaryKeyBar` holds, for `role`.
    @ViewBuilder
    func key(_ role: KeyRole, named name: String) -> some View {
        let tap = { tapKey(named: name) }
        switch role {
        case .start:
            Button("Start", systemImage: "play.fill", action: tap)
        case let .log(text):
            Button(text, action: tap)
                .accessibilityIdentifier("workout.key")
        case let .back(exercise, isAbove):
            Button(action: tap) {
                // Whole, wrapping at the largest text sizes rather than cut short.
                Label(exercise, systemImage: isAbove ? "arrow.up" : "arrow.down")
            }
            .accessibilityLabel("Go to current exercise, \(exercise)")
            .accessibilityIdentifier("workout.key")
        case .closing:
            Button("Log last set", action: tap)
                .accessibilityIdentifier("workout.key")
        case .finish:
            Button("Finish workout", action: tap)
                .accessibilityIdentifier("workout.key")
        }
    }

    /// The key's shape in a workout: a pill at the bar's trailing end in the pill build, else as
    /// wide as Start.
    var keyShape: PrimaryKeyShape {
        #if LOG_KEY_PILL
        session.workout == nil || isStarting ? .wide : .pill
        #else
        .wide
        #endif
    }

    /// A tap on the key. Out of a workout, Start. After the last set, Finish workout. Otherwise,
    /// where the current exercise is mostly out of view when the tap lands, as on a list still
    /// moving away under "Log set", the list goes back to it and nothing is logged: the words
    /// change only once a scroll has ended (`settleKeyRole()`), the place at once.
    func tapKey(named name: String) {
        guard session.workout != nil, !isStarting else { return pressStart() }
        guard !isMovingOn else { return }
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
    /// view, else none. Called once a scroll has ended or a move has landed, never mid-scroll,
    /// so the words don't change under a finger. Not while moving on, whose row passes through
    /// the edge, nor before a relaunch has opened on the current exercise.
    func settleKeyRole() {
        guard !isMovingOn, !opensOnCurrent else { return }
        let way: VerticalEdge? = if currentID != nil, let place = currentPlace, place.isMostlyOut {
            place.isAbove ? .top : .bottom
        } else {
            nil
        }
        guard way != keyWayBack else { return }
        withAnimation(.snappy) { keyWayBack = way }
    }

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

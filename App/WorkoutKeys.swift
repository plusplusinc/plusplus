import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// End, in the bar while a workout is in progress, and held there, asking nothing, while a
/// finish holds the screen still; it only asks: the screen presents its dialog, whose choices
/// are to finish the workout session or discard it.
struct EndButton: View {
    let action: () -> Void

    var body: some View {
        Button("End", action: action)
            .accessibilityLabel("End workout")
            .hiddenBehindDrawer()
    }
}

/// What End's dialog chooses between, a workout screen's own finish and discard: handed by a
/// workout pushed on the Workouts screen to that screen, which presents the dialog outside its
/// navigation stack (`endWorkoutDialog`).
struct EndChoices {
    let finish: () -> Void
    let discard: () -> Void
}

extension View {
    /// End's dialog for a pushed workout, showing while `choices` holds its screen's.
    func endWorkoutDialog(
        choosing choices: Binding<EndChoices?>,
        session: AppSession,
    ) -> some View {
        let asked = choices.wrappedValue
        return endWorkoutDialog(
            isPresented: Binding { choices.wrappedValue != nil } set: { isPresented in
                if !isPresented {
                    choices.wrappedValue = nil
                }
            },
            session: session,
            finish: { asked?.finish() },
            discard: { asked?.discard() },
        )
    }

    /// Asks whether to finish the workout and keep it, or discard it, with `finish` and
    /// `discard` the screen's; the scratch app's dialog. Attached to the whole screen,
    /// navigation stack included, so iOS shows it centered: attached to Finish or to the stack's
    /// content, it came as a popover with an arrow.
    func endWorkoutDialog(
        isPresented: Binding<Bool>,
        session: AppSession,
        finish: @escaping () -> Void,
        discard: @escaping () -> Void,
    ) -> some View {
        confirmationDialog(
            "End this workout?",
            isPresented: isPresented,
            titleVisibility: .visible,
        ) {
            // Only with something to keep: until a set is done, it can only be discarded.
            if session.workoutSession?.offersFinish == true {
                Button("Finish workout", action: finish)
            }
            Button("Discard workout", role: .destructive, action: discard)
            Button("Keep going", role: .cancel) { }
        } message: {
            // Read with the buttons: it names Finish only when Finish shows.
            if session.workoutSession?.offersFinish == true {
                Text("Finish keeps what you logged; Discard deletes the workout.")
            } else {
                Text("Nothing has been logged yet.")
            }
        }
    }
}

/// The workout's time, in the bar, which a tap pauses or resumes. It ticks on the elapsed
/// time's whole seconds while running, and draws once while paused.
struct WorkoutTimeKey: View {
    let workoutSession: WorkoutSession
    /// The screen's pause or resume (`WorkoutScreen.togglePause()`), which animates the key.
    let togglePause: () -> Void

    @Environment(\.locale) private var locale
    /// The moment the time is drawn for: now, as each whole second of it comes (`tick()`).
    @State private var shownAt = Date.now

    var body: some View {
        Button(action: togglePause) {
            label(at: workoutSession.pausedAt ?? shownAt)
        }
        .hiddenBehindDrawer()
        .accessibilityIdentifier("workout.time")
        .task(id: Ticking(clockStart: workoutSession.clockStart, runs: workoutSession.runs)) {
            await tick()
        }
    }

    /// Sets `shownAt` now, then at each whole second of the elapsed time while it runs. Not a
    /// `TimelineView`: one in a bar item and one ticking in the screen ("Start in") rendered
    /// each other's hosts in a layout loop, holding the main thread a quarter second after each
    /// tick, the time showing late (UIKit's layout feedback loop debugger).
    private func tick() async {
        shownAt = .now
        guard workoutSession.runs else { return }
        while true {
            let next = workoutSession.nextSecond(after: shownAt)
            let wait = next.timeIntervalSinceNow
            if wait > 0 {
                guard await (try? Task.sleep(for: .seconds(wait), tolerance: .zero)) != nil
                else { return }
            }
            // Woken a hair early, the time still turns over: never drawn short of `next`.
            shownAt = max(.now, next)
        }
    }

    private func label(at date: Date) -> some View {
        let elapsed = workoutSession.elapsed(at: date)
        return WorkoutTimeLabel(
            WorkoutSession.elapsedText(elapsed, locale: locale),
            isPaused: workoutSession.isPaused,
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(workoutSession.isPaused ? "Resume" : "Pause")
        .accessibilityValue(WorkoutSession.spokenElapsed(elapsed, locale: locale))
    }
}

/// What the time's ticking runs on: a pause, a resume, or the end starts it again.
private struct Ticking: Equatable {
    let clockStart: Date
    let runs: Bool
}

extension WorkoutSession {
    /// Whether its time is running on: in progress and not paused.
    fileprivate var runs: Bool {
        isInProgress && !isPaused
    }
}

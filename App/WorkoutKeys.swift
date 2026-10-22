import DesignSystem
import SwiftUI
import WorkoutStore

/// End, in the bar while a workout runs, which only asks: the screen presents its dialog, whose
/// choices are to finish the workout or discard it.
struct EndButton: View {
    let action: () -> Void

    var body: some View {
        Button("End", action: action)
            .accessibilityLabel("End workout")
            .hiddenBehindDrawer()
    }
}

extension View {
    /// Asks whether to finish the workout and keep it, or discard it, with `end` running the
    /// choice in the screen's sequence; the scratch app's dialog. Attached to the whole screen,
    /// navigation stack included, so iOS shows it centered: attached to Finish or to the stack's
    /// content, it came as a popover with an arrow.
    func endWorkoutDialog(
        isPresented: Binding<Bool>,
        session: RoutineSession,
        routineName: String,
        end: @escaping (@escaping () -> Void) -> Void,
    ) -> some View {
        confirmationDialog(
            "End this workout?",
            isPresented: isPresented,
            titleVisibility: .visible,
        ) {
            // Only with something to keep: until a set is done, it can only be discarded.
            if session.workout?.offersFinish == true {
                Button("Finish workout") {
                    end { session.finish(routineName: routineName) }
                }
            }
            Button("Discard workout", role: .destructive) {
                end(session.discard)
            }
            Button("Keep going", role: .cancel) { }
        } message: {
            // Read with the buttons: it names Finish only when Finish shows.
            if session.workout?.offersFinish == true {
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
    let session: RoutineSession
    let workout: Workout

    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            session.togglePause()
        } label: {
            // One timeline whether running or paused, so the label stays the same view and
            // its icon can change from one symbol to the other.
            TimelineView(SecondsSchedule(workout: workout)) { context in
                label(at: workout.pausedAt ?? context.date)
            }
        }
        .hiddenBehindDrawer()
        .accessibilityIdentifier("workout.time")
    }

    private func label(at date: Date) -> some View {
        let elapsed = workout.elapsed(at: date)
        return WorkoutTimeLabel(
            Workout.elapsedText(elapsed, locale: locale),
            isPaused: workout.isPaused,
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(workout.isPaused ? "Resume" : "Pause")
        .accessibilityValue(Workout.spokenElapsed(elapsed, locale: locale))
    }
}

/// The whole seconds of a workout's elapsed time while it runs; while paused, once.
private struct SecondsSchedule: TimelineSchedule {
    let workout: Workout

    func entries(from startDate: Date, mode: Mode) -> AnyIterator<Date> {
        if workout.isPaused {
            return AnyIterator([startDate].makeIterator())
        }
        return AnyIterator(
            PeriodicTimelineSchedule(from: workout.clockStart, by: 1)
                .entries(from: startDate, mode: mode),
        )
    }
}

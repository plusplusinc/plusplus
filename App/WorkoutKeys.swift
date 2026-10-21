import DesignSystem
import SwiftUI
import WorkoutStore

/// Finish, in the bar while a workout runs. It asks first: finish and keep the workout, or
/// discard it.
struct FinishButton: View {
    let session: RoutineSession
    /// The name the routine shows, kept with the finished workout.
    let routineName: String
    /// Ends the workout with the change given, in the screen's sequence.
    let end: (@escaping () -> Void) -> Void

    @State private var isConfirming = false

    var body: some View {
        Button("Finish") {
            isConfirming = true
        }
        .hiddenBehindDrawer()
        // Attached to the button, so the dialog comes from it.
        .confirmationDialog("", isPresented: $isConfirming, titleVisibility: .hidden) {
            Button("Finish") {
                end { session.finish(routineName: routineName) }
            }
            Button("Discard workout", role: .destructive) {
                end(session.discard)
            }
            Button("Cancel", role: .cancel) { }
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

    func entries(from startDate: Date, mode _: Mode) -> AnyIterator<Date> {
        if workout.isPaused {
            return AnyIterator([startDate].makeIterator())
        }
        return AnyIterator(
            PeriodicTimelineSchedule(from: workout.clockStart, by: 1)
                .entries(from: startDate, mode: .normal),
        )
    }
}

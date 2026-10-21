import DesignSystem
import SwiftUI
import WorkoutStore

/// Finish, in the bar while a workout runs. It asks first: finish and keep the workout, or
/// discard it.
struct FinishButton: View {
    let session: RoutineSession
    /// The name the routine shows, kept with the finished workout.
    let routineName: String

    @State private var isConfirming = false

    var body: some View {
        Button("Finish") {
            isConfirming = true
        }
        .hiddenBehindDrawer()
        // Attached to the button, so the dialog comes from it.
        .confirmationDialog("", isPresented: $isConfirming, titleVisibility: .hidden) {
            // The current exercise goes back to its resting size as Start comes back.
            Button("Finish") {
                withAnimation(.snappy(duration: 0.4)) { session.finish(routineName: routineName) }
            }
            Button("Discard workout", role: .destructive) {
                withAnimation(.snappy(duration: 0.4)) { session.discard() }
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
            if let pausedAt = workout.pausedAt {
                label(at: pausedAt)
            } else {
                TimelineView(.periodic(from: workout.clockStart, by: 1)) { context in
                    label(at: context.date)
                }
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

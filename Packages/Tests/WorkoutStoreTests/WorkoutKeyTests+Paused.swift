import Foundation
import Testing
@testable import WorkoutStore

/// The key while the workout is paused: Continue, which resumes it, logging, skipping, and
/// extending nothing, ahead of every role but Start and Finish workout.
extension WorkoutKeyTests {
    static func pausedRows(_ on: Seed) -> [Row] {
        [
            Row(
                "Paused on a set: Continue, logging nothing",
                on.key(logged: 0, paused: true),
                says: .continueWorkout,
                taps: .continueWorkout,
            ),
            Row(
                "Paused with the current exercise scrolled away: Continue, not back",
                on.key(logged: 0, wayBack: .down, isScrolledAway: true, paused: true),
                says: .continueWorkout,
                taps: .continueWorkout,
            ),
            Row(
                "Paused in a rest: Continue in the rest's keys' place, which change nothing",
                on.key(
                    logged: 1,
                    phase: resting(on.first, leadingTo: .nextSet, to: .settled),
                    paused: true,
                ),
                says: .continueWorkout,
                taps: .continueWorkout,
            ),
            Row(
                "Paused after the last set: Finish workout, which finishes",
                on.key(logged: 4, paused: true),
                says: .finish,
                taps: .finish,
            ),
            Row(
                "Paused out of a workout: Start",
                on.key(logged: nil, phase: .idle, paused: true),
                says: .start,
                taps: .start,
            ),
        ]
    }
}

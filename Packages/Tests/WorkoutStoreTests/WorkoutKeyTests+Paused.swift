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
                "Paused in a reps set's Start in: Continue, though no key shows while it runs",
                on.key(logged: 0, phase: .timing(.startIn), paused: true),
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

    @Test("Paused, Continue shows where no key would: in Start in and a skipped rest's hold")
    func pausedKeyShows() throws {
        let on = try Seed()
        let startIn = on.key(logged: 0, phase: .timing(.startIn), paused: true)
        #expect(!startIn.waitsToStart, "Start in")
        var skipped = Self.resting(on.first, leadingTo: .nextSet, to: .settled)
        skipped.skipRest(left: 20, leave: 100)
        let held = on.key(logged: 1, phase: skipped, paused: true)
        #expect(held.role == .continueWorkout, "A skipped rest's hold")
        #expect(!held.waitsToStart, "A skipped rest's hold")
    }

    /// Where a pause or a resume brings the key in or takes it away, the screen animates it as
    /// "Start in"'s end brings the set's key in; elsewhere the key only changes kind.
    @Test("A pause moves the key only in Start in and a skipped rest's hold, paused or not")
    func pauseMovesKey() throws {
        let on = try Seed()
        var skipped = Self.resting(on.first, leadingTo: .nextSet, to: .settled)
        skipped.skipRest(left: 20, leave: 100)
        let rest = Self.resting(on.first, leadingTo: .nextSet, to: .settled)
        let moves: [String: (Bool) -> WorkoutKey] = [
            "Start in": { on.key(logged: 0, phase: .timing(.startIn), paused: $0) },
            "A skipped rest's hold": { on.key(logged: 1, phase: skipped, paused: $0) },
        ]
        let stays: [String: (Bool) -> WorkoutKey] = [
            "Log set": { on.key(logged: 0, paused: $0) },
            "A rest": { on.key(logged: 1, phase: rest, paused: $0) },
            "Scrolled away": {
                on.key(logged: 1, wayBack: .up, isScrolledAway: true, paused: $0)
            },
        ]
        for paused in [false, true] {
            for (name, key) in moves {
                #expect(key(paused).pauseMovesKey, "\(name), paused: \(paused)")
            }
            for (name, key) in stays {
                #expect(!key(paused).pauseMovesKey, "\(name), paused: \(paused)")
            }
        }
    }
}

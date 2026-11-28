import SwiftUI

/// The one task that plays a workout's timed beats on the workout screen, Start's, a logged
/// set's, and End's motion, held so that what stops a sequence can cancel it. Nothing stored
/// waits on it: End's change to the store is made before its motion plays. Not observed, as
/// `RowFrames` isn't: nothing is drawn from it.
final class SequenceTask {
    private var task: Task<Void, Never>?

    /// Cancels the sequence playing, if one is, and plays `beats`. Made in the caller's turn, as
    /// a `Task { }` would be, so its first statement runs on a later turn of the run loop.
    func run(_ beats: @escaping @MainActor () async throws -> Void) {
        task?.cancel()
        task = Task { try? await beats() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Sleeps to `deadline`, then throws if the sequence was cancelled meanwhile: a sleep that had
/// already ended when it was cancelled resumes without throwing.
func beat(until deadline: ContinuousClock.Instant) async throws {
    try await Task.sleep(until: deadline, tolerance: .zero, clock: .continuous)
    try Task.checkCancellation()
}

/// Resumes on a later turn of the run loop, after the update the caller's changes go into, or
/// throws if the sequence was cancelled meanwhile.
func laterTurn() async throws {
    await Task.yield()
    try Task.checkCancellation()
}

extension WorkoutScreen {
    /// The screen going away: the sequence playing stops, and the phase settles at once to what
    /// the store holds, so the key never waits on a workout that is gone, or ignores one there,
    /// a rest still running settled in place, as a relaunch opens on it.
    /// A row's sheet still set closes: with no screen to show it, it kept the drawer shut.
    func stopSequence() {
        session.closeRowSheet()
        sequence.cancel()
        // A timed set the stopped sequence was landing on counts from now; stopped within
        // Start, the first set's "Start in" begins here, as at Start's landing.
        session.landOnFirstSet()
        withTransaction(\.disablesAnimations, true) {
            phase.settleAtOnce(resuming: live, at: .now)
            closingRoomTop = nil
            isCrossfading = false
            // Start's ride down, and any lift drawn for a motion, are over.
            endStartRide()
            growthLift = 0
            underBarCut = 0
            if session.workoutSession == nil {
                // Start pressed and stopped before the workout began: nothing has changed.
                isMakingRoom = false
            }
        }
        letRoomGo()
    }
}

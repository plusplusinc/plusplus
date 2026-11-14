import SwiftUI

/// The one task that plays a logged set's timed beats on the routine screen, held so that what
/// stops a sequence can cancel it. Not observed, as `RowFrames` isn't: nothing is drawn from it.
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

extension RoutineScreen {
    /// The screen going away: the sequence playing stops, and the workout drawn is where it was
    /// going, at once.
    func stopSequence() {
        sequence.cancel()
        withTransaction(\.disablesAnimations, true) {
            phase.settleAtOnce()
            closingRoomTop = nil
            isCrossfading = false
            if session.workout == nil {
                // Start pressed and stopped before the workout began: nothing has changed.
                isMakingRoom = false
                startDrop = 0
            }
        }
        letRoomGo()
    }
}

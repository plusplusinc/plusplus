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

extension RoutineScreen {
    /// The screen going away: the sequence playing stops, and the workout drawn is where it was
    /// going, at once.
    func stopSequence() {
        sequence.cancel()
        withTransaction(\.disablesAnimations, true) {
            playback.show()
            exerciseMove = nil
            closingRoomTop = nil
        }
        _ = playback.end()
        letRoomGo()
    }
}

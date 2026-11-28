import OSLog
import WorkoutStore

/// The queues the session writes to the store through, each landing its writes in order: the
/// open workout's saves, newest only, and a workout session's writes, every one. Apple Health's
/// queue, which follows the second's shape, is in `AppSession+Health.swift`.
extension AppSession {
    /// A workout to save, and whether to keep it once it is empty, as while it is in progress.
    struct WorkoutSave {
        let workout: Workout
        let keepsEmpty: Bool
    }

    enum WorkoutSessionWrite {
        case save(WorkoutSession)
        case discard(WorkoutSession.ID)
    }

    enum WorkoutSessionQueueEntry {
        case write(WorkoutSessionWrite)
        /// A finished workout session deleted from Log, after any write of it still on its way.
        case delete(WorkoutSession.ID)
        /// Every write before it has landed.
        case landed(CheckedContinuation<Void, Never>)
    }

    static func startSaving(
        to store: Store?,
    ) -> (AsyncStream<WorkoutSave>.Continuation, Task<Void, Never>) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: WorkoutSave.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let task = Task {
            for await version in stream {
                do {
                    try await store?.save(version.workout, keepsEmpty: version.keepsEmpty)
                } catch {
                    Logger.session.error("The workout didn't save: \(error)")
                }
            }
        }
        return (continuation, task)
    }

    static func startWritingWorkoutSessions(
        to store: Store?,
    ) -> AsyncStream<WorkoutSessionQueueEntry>.Continuation {
        let (stream, continuation) = AsyncStream.makeStream(
            of: WorkoutSessionQueueEntry.self,
            bufferingPolicy: .unbounded,
        )
        Task {
            for await entry in stream {
                do {
                    switch entry {
                    case let .write(.save(workoutSession)): try await store?.save(workoutSession)
                    case let .write(.discard(id)): try await store?.discardWorkoutSession(id)
                    case let .delete(id): try await store?.deleteWorkoutSession(id)
                    case let .landed(done): done.resume()
                    }
                } catch {
                    Logger.session.error("A workout session's write didn't land: \(error)")
                }
            }
        }
        return continuation
    }

    /// Returns once every workout session write sent so far has landed, or failed.
    func workoutSessionWritesLanded() async {
        await withCheckedContinuation { done in workoutSessionWrites.yield(.landed(done)) }
    }
}

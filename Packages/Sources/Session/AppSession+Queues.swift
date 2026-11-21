import OSLog
import WorkoutStore

/// The two queues the session writes through, each landing its writes in the store in order: the
/// open workout's saves, newest only, and a logged workout's writes, every one.
extension AppSession {
    /// A workout to save, and whether to keep it once it is empty, as while it is in progress.
    struct WorkoutSave {
        let workout: Workout
        let keepsEmpty: Bool
    }

    enum LoggedWorkoutWrite {
        case save(LoggedWorkout)
        case discard(LoggedWorkout.ID)
    }

    enum LoggedWorkoutQueueEntry {
        case write(LoggedWorkoutWrite)
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

    static func startWritingLoggedWorkouts(
        to store: Store?,
    ) -> AsyncStream<LoggedWorkoutQueueEntry>.Continuation {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LoggedWorkoutQueueEntry.self,
            bufferingPolicy: .unbounded,
        )
        Task {
            for await entry in stream {
                do {
                    switch entry {
                    case let .write(.save(loggedWorkout)): try await store?.save(loggedWorkout)
                    case let .write(.discard(id)): try await store?.discardLoggedWorkout(id)
                    case let .landed(done): done.resume()
                    }
                } catch {
                    Logger.session.error("The logged workout didn't save: \(error)")
                }
            }
        }
        return continuation
    }
}

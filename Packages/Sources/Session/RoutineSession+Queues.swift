import OSLog
import WorkoutStore

/// The two queues the session writes through, each landing its writes in the store in order: the
/// open routine's saves, newest only, and a workout's writes, every one.
extension RoutineSession {
    /// A routine to save, and whether to keep it once it is empty, as while its workout runs.
    struct RoutineSave {
        let routine: Routine
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
        to store: RoutineStore?,
    ) -> (AsyncStream<RoutineSave>.Continuation, Task<Void, Never>) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: RoutineSave.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let task = Task {
            for await version in stream {
                do {
                    try await store?.save(version.routine, keepsEmpty: version.keepsEmpty)
                } catch {
                    Logger.session.error("The routine didn't save: \(error)")
                }
            }
        }
        return (continuation, task)
    }

    static func startWritingWorkouts(
        to store: RoutineStore?,
    ) -> AsyncStream<LoggedWorkoutQueueEntry>.Continuation {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LoggedWorkoutQueueEntry.self,
            bufferingPolicy: .unbounded,
        )
        Task {
            for await entry in stream {
                do {
                    switch entry {
                    case let .write(.save(workout)): try await store?.save(workout)
                    case let .write(.discard(id)): try await store?.discardWorkout(id)
                    case let .landed(done): done.resume()
                    }
                } catch {
                    Logger.session.error("The workout didn't save: \(error)")
                }
            }
        }
        return continuation
    }
}

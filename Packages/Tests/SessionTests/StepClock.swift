import Synchronization

/// A clock whose time moves only when a test advances it, so timed beats run in order with no
/// real waiting. `sleeper()` returns once something is asleep on it, which is how a test knows a
/// beat before has run.
final class StepClock: Clock {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        func duration(to other: Self) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let wake: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Sleeper] = []
        var waitingForSleeper: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var now: Instant {
        state.withLock(\.now)
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: Wake) in
                list(Sleeper(id: id, deadline: deadline, wake: continuation))
            }
        } onCancel: {
            cancel(id)
        }
    }

    private typealias Wake = CheckedContinuation<Void, any Error>

    /// Puts a sleeper to sleep, or wakes it at once when its deadline has passed or its task is
    /// cancelled, and lets anyone waiting for a sleeper go on.
    private func list(_ sleeper: Sleeper) {
        let cancelled = Task.isCancelled
        let outcome: (wake: Bool, waiting: [CheckedContinuation<Void, Never>]) = state
            .withLock { state in
                // The flag is set before the cancel handler runs, so a cancel that ran before
                // this sleeper was listed is caught here.
                if cancelled || sleeper.deadline <= state.now {
                    return (true, [])
                }
                state.sleepers.append(sleeper)
                let waiting = state.waitingForSleeper
                state.waitingForSleeper = []
                return (false, waiting)
            }
        if outcome.wake {
            if cancelled {
                sleeper.wake.resume(throwing: CancellationError())
            } else {
                sleeper.wake.resume()
            }
        }
        for waiter in outcome.waiting {
            waiter.resume()
        }
    }

    private func cancel(_ id: Int) {
        let cancelled: Sleeper? = state.withLock { state in
            guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return state.sleepers.remove(at: index)
        }
        cancelled?.wake.resume(throwing: CancellationError())
    }

    /// Moves time on by `duration`, waking every sleeper whose deadline it reaches.
    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due {
            sleeper.wake.resume()
        }
    }

    /// Returns once something is asleep on the clock.
    func sleeper() async {
        await withCheckedContinuation { continuation in
            let asleep = state.withLock { state in
                if state.sleepers.isEmpty {
                    state.waitingForSleeper.append(continuation)
                    return false
                }
                return true
            }
            if asleep {
                continuation.resume()
            }
        }
    }

    /// Whether anything is asleep on the clock.
    var hasSleeper: Bool {
        state.withLock { !$0.sleepers.isEmpty }
    }
}

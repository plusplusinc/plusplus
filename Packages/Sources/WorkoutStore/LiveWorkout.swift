import Foundation

/// A workout in progress on its routine: where it is (the set to do next, its exercise, whether
/// it is done, which rows are finished, which show their bars) and what logging a set leads to.
/// The routine is the one on screen, edits included, so a row added, moved, or deleted
/// mid-workout counts at once.
public struct LiveWorkout: Equatable, Sendable {
    public var routine: Routine
    public var workout: Workout

    public init(routine: Routine, workout: Workout) {
        self.routine = routine
        self.workout = workout
    }

    /// The set it does next: the first in the routine's order not yet logged. None once every
    /// one is.
    public var currentSet: PlannedSet? {
        routine.nextSet(after: workout.sets)
    }

    /// The exercise it is on: the row of the set it does next.
    public var currentExercise: RoutineExercise? {
        currentSet.flatMap { set in routine.exercises.first { $0.id == set.row } }
    }

    /// Whether every planned set is logged, so what is left is to finish it. Never on a routine
    /// with no exercises, which has nothing to finish.
    public var isDone: Bool {
        !routine.exercises.isEmpty && currentSet == nil
    }

    /// The rows with every set logged, whose nodes show them done. Never a row with none
    /// planned.
    public var finishedRows: Set<RoutineExercise.ID> {
        Set(routine.exercises.lazy.map(\.id).filter { id in
            let progress = routine.progress(of: id, logged: workout.sets)
            return progress.total > 0 && progress.done == progress.total
        })
    }

    /// The set bars a row shows: on the current exercise always, from its first set; on any other
    /// only once started and until finished, where its node shows it done. Nil for none.
    public func bars(of id: RoutineExercise.ID) -> (done: Int, total: Int)? {
        let progress = routine.progress(of: id, logged: workout.sets)
        guard id == currentSet?.row
            || routine.isStarted(id, logged: workout.sets) && progress.done < progress.total
        else { return nil }
        return progress
    }

    /// What the key that logs the current set says ("Log set", "Log left", "Log last set"). None
    /// once every set is logged.
    public var logText: String? {
        currentSet.map { routine.logText(for: $0, after: workout.sets) }
    }

    /// What logging `set` leads to, from where the workout is.
    public func step(logging set: PlannedSet) -> Step {
        let done = Set(workout.sets.map(\.planned)).union([set])
        guard let next = routine.nextSet(notIn: done) else { return .last }
        guard next.row != set.row else { return .nextSet }
        let rows = routine.exercises.map(\.id)
        let isBack = (rows.firstIndex(of: next.row) ?? 0) < (rows.firstIndex(of: set.row) ?? 0)
        return .nextExercise(
            to: next,
            isBack: isBack,
            startsRound: isBack && next.round != set.round && routine.isInSuperset(next.row),
        )
    }

    /// The workout as it stood before its newest logged sets, while each is in `unshown`: logged
    /// and stored, but not yet drawn. Only from the end, so a set counts as unshown only while
    /// no set it doesn't hold was logged after it.
    public func hiding(_ unshown: [PlannedSet]) -> Self {
        guard !unshown.isEmpty else { return self }
        var hidden = self
        while let last = hidden.workout.sets.last, unshown.contains(last.planned) {
            hidden.workout.sets.removeLast()
        }
        return hidden
    }
}

extension LiveWorkout {
    /// What logging a set leads to.
    public enum Step: Equatable, Sendable {
        /// The next set is on the same exercise.
        case nextSet
        /// On to another exercise, at `to`. `isBack`: its row is above the one left, round a
        /// superset's loop or to a row moved above. `startsRound`: back to a superset's member, in
        /// a later round.
        case nextExercise(to: PlannedSet, isBack: Bool, startsRound: Bool)
        /// The last planned set: nothing follows.
        case last
    }
}

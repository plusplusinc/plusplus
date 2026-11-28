import Foundation

/// A workout in progress: its plan and what is logged so far. It answers where it is (the set
/// to do next, its exercise, whether it is done, which rows are finished, which show their
/// bars) and what logging a set leads to. The workout is the one on screen, edits
/// included, so a row added, moved, or deleted mid-workout counts at once.
public struct LiveWorkout: Equatable, Sendable {
    public var workout: Workout
    public var workoutSession: WorkoutSession

    public init(workout: Workout, workoutSession: WorkoutSession) {
        self.workout = workout
        self.workoutSession = workoutSession
    }

    /// The set it does next: the first in the workout's order not yet logged. None once every
    /// one is.
    public var currentSet: PlannedSet? {
        workout.nextSet(after: workoutSession.sets)
    }

    /// The exercise it is on: the row of the set it does next.
    public var currentExercise: WorkoutExercise? {
        currentSet.flatMap { set in workout.exercises.first { $0.id == set.row } }
    }

    /// Whether every planned set is logged, so what is left is to finish it. Never on a workout
    /// with no exercises, which has nothing to finish.
    public var isDone: Bool {
        !workout.exercises.isEmpty && currentSet == nil
    }

    /// The rows with every set logged, whose nodes show them done. Never a row with none
    /// planned.
    public var finishedRows: Set<WorkoutExercise.ID> {
        Set(workout.exercises.lazy.map(\.id).filter { id in
            let progress = workout.progress(of: id, logged: workoutSession.sets)
            return progress.total > 0 && progress.done == progress.total
        })
    }

    /// The set bars a row shows: on the current exercise always, from its first set; on any other
    /// only once started and until finished, where its node shows it done. Nil for none.
    public func bars(of id: WorkoutExercise.ID) -> RowProgress? {
        let progress = workout.progress(of: id, logged: workoutSession.sets)
        guard id == currentSet?.row
            || workout.isStarted(id, logged: workoutSession.sets) && progress.done < progress.total
        else { return nil }
        return progress
    }

    /// What the key that logs the current set says ("Log set", "Log left", "Log last set"). None
    /// once every set is logged.
    public var logText: String? {
        currentSet.map { workout.logText(for: $0, after: workoutSession.sets) }
    }

    /// What logging `set` leads to, from where the workout is, with `earlier` logged first, as a
    /// set's first side is before its second.
    public func step(logging set: PlannedSet, after earlier: [PlannedSet] = []) -> Step {
        let done = Set(workoutSession.sets.map(\.planned)).union(earlier).union([set])
        guard let next = workout.nextSet(notIn: done) else { return .last }
        guard next.row != set.row else { return .nextSet }
        let rows = workout.exercises.map(\.id)
        let isBack = (rows.firstIndex(of: next.row) ?? 0) < (rows.firstIndex(of: set.row) ?? 0)
        return .nextExercise(
            to: next,
            isBack: isBack,
            startsRound: isBack && next.round != set.round && workout.isInSuperset(next.row),
        )
    }

    /// The workout as it stood before its newest logged sets, while each is in `unshown`: logged
    /// and stored, but not yet drawn. Only from the end, so a set counts as unshown only while
    /// no set it doesn't hold was logged after it.
    public func hiding(_ unshown: [PlannedSet]) -> Self {
        guard !unshown.isEmpty else { return self }
        var hidden = self
        while let last = hidden.workoutSession.sets.last, unshown.contains(last.planned) {
            hidden.workoutSession.sets.removeLast()
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

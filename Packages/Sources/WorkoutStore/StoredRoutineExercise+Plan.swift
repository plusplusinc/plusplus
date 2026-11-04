import OSLog

extension StoredRoutineExercise {
    /// Writes every field of the plan, clearing the ones it doesn't use, and setting only the
    /// fields that differ, so an unchanged row stays clean. A row's plan is stored even when it
    /// is the default, so it keeps what was shown if a later version's default changes; a rest
    /// the user never set stays nil, so it follows the reps.
    func write(_ plan: ExercisePlan) {
        let (newReps, newSeconds): (Int?, Int?) =
            switch plan.target {
            case let .reps(count): (count, nil)
            case let .time(time): (nil, time)
            }
        update(\.sets, to: plan.sets)
        update(\.reps, to: newReps)
        update(\.seconds, to: newSeconds)
        update(\.weight, to: plan.weight?.amount)
        update(\.weightUnit, to: plan.weight?.unit.rawValue)
        update(\.rest, to: plan.rest)
    }

    /// Writes a superset's gaps as they are, nil for one never set.
    func write(_ round: RoundRest) {
        update(\.roundRest, to: round.afterRound)
    }

    /// The stored superset gaps, each nil when never set or out of range.
    var round: RoundRest {
        RoundRest(afterRound: Self.gap(roundRest))
    }

    private static func gap(_ seconds: Int?) -> Int? {
        seconds.flatMap { PlanLimits.rest.contains($0) ? $0 : nil }
    }

    /// The stored plan, field by field: a field never stored, out of range, or for another
    /// measure reads as the exercise's default, a weight in `weightUnit`, the region's. A weight
    /// shows only on an exercise that holds one, and in the unit it was saved in.
    func plan(for exercise: Exercise, weightUnit: WeightUnit) -> ExercisePlan {
        let fallback = exercise.defaultPlan(in: weightUnit)
        let target: SetTarget =
            switch fallback.target {
            case .reps:
                reps.flatMap { PlanLimits.reps.contains($0) ? .reps($0) : nil } ?? fallback.target
            case .time:
                seconds.flatMap { PlanLimits.seconds.contains($0) ? .time(seconds: $0) : nil }
                    ?? fallback.target
            }
        return ExercisePlan(
            sets: sets.flatMap { PlanLimits.sets.contains($0) ? $0 : nil } ?? fallback.sets,
            target: target,
            weight: exercise.load == nil ? nil : storedWeight ?? fallback.weight,
            rest: Self.gap(rest),
        )
    }

    private var storedWeight: Weight? {
        guard let weight, PlanLimits.weight.contains(weight), let weightUnit else { return nil }
        guard let unit = WeightUnit(rawValue: weightUnit) else {
            Logger.storage
                .error("Read an unknown weight unit \(weightUnit, privacy: .public) as the default")
            return nil
        }
        return Weight(weight, unit)
    }
}

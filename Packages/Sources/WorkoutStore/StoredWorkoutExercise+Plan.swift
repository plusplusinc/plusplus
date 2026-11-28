import OSLog

extension StoredWorkoutExercise {
    /// Writes every field of the plan, setting only the fields that differ, so an unchanged row
    /// stays clean. A row's plan is stored even when it is the default, so it keeps what was
    /// shown if a later version's default changes; a rest the user never set stays nil, so it
    /// follows the reps. The other measure's number, and a weight while its exercise holds
    /// none, are kept rather than cleared: an exercise someone changes from reps to time and
    /// back, or to bodyweight and back, comes back with the numbers it had.
    func write(_ plan: ExercisePlan) {
        update(\.sets, to: plan.sets)
        switch plan.target {
        case let .reps(count): update(\.reps, to: count)
        case let .time(time): update(\.seconds, to: time)
        }
        if let weight = plan.weight {
            update(\.weight, to: weight.amount)
            update(\.weightUnit, to: weight.unit.rawValue)
        }
        update(\.rest, to: plan.rest.lastByHand)
        update(\.isRestAuto, to: plan.rest.isAuto)
    }

    /// Writes a superset's rest as it is, nil for one never set.
    func write(roundRest: Rest) {
        update(\.roundRest, to: roundRest.lastByHand)
        update(\.isRoundRestAuto, to: roundRest.isAuto)
    }

    /// The stored superset rest.
    var storedRoundRest: Rest {
        Self.rest(seconds: roundRest, isAuto: isRoundRestAuto)
    }

    /// A stored rest: Auto, keeping the seconds if any; or set by hand, unless its seconds are
    /// missing or out of range, which read as Auto, never set.
    private static func rest(seconds: Int?, isAuto: Bool) -> Rest {
        let seconds = seconds.flatMap { PlanLimits.rest.contains($0) ? $0 : nil }
        return isAuto ? .auto(kept: seconds) : seconds.map(Rest.byHand(seconds:)) ?? .neverSet
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
            rest: Self.rest(seconds: rest, isAuto: isRestAuto),
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

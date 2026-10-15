import OSLog

extension StoredRoutineExercise {
    /// Writes every field of the plan, clearing the ones it doesn't use.
    func write(_ plan: ExercisePlan) {
        sets = plan.sets
        switch plan.target {
        case let .reps(count):
            reps = count
            seconds = nil
        case let .time(time):
            reps = nil
            seconds = time
        }
        weight = plan.weight?.amount
        weightUnit = plan.weight?.unit.rawValue
    }

    /// The stored plan, field by field: a field never stored, out of range, or for another
    /// measure reads as the exercise's default, and a weight only on an exercise that holds one.
    func plan(for exercise: Exercise) -> ExercisePlan {
        let fallback = exercise.defaultPlan
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
            weight: exercise.load == nil ? nil : storedWeight,
        )
    }

    private var storedWeight: Weight? {
        guard let weight, weight > 0, let weightUnit else { return nil }
        guard let unit = WeightUnit(rawValue: weightUnit) else {
            Logger.storage
                .error("Read an unknown weight unit \(weightUnit, privacy: .public) as not set")
            return nil
        }
        return Weight(weight, unit)
    }
}

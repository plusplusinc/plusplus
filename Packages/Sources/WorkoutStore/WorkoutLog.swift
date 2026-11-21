import Foundation

/// The record of finished workouts, newest first, and its readings: an opened workout's
/// exercises against the time before, what went up over four weeks, and what has been left
/// alone. Windows are calendar days: a workout is `n` days ago when `n` days lie between the
/// start of the day it finished and the start of today.
public struct WorkoutLog: Equatable, Sendable {
    /// Finished workouts, the latest finish first.
    public let workouts: [Workout]

    public init(workouts: [Workout]) {
        self.workouts = workouts
            .filter { !$0.isInProgress }
            .sorted { one, other in
                let (oneEnd, otherEnd) = (
                    one.endedAt ?? .distantPast,
                    other.endedAt ?? .distantPast,
                )
                return oneEnd != otherEnd ? oneEnd > otherEnd : one.id.uuidString < other.id
                    .uuidString
            }
    }

    public func workout(id: Workout.ID) -> Workout? {
        workouts.first { $0.id == id }
    }

    /// The workout's exercises in the order done, each with the change from the newest workout
    /// that finished before this one started and has a set of the same exercise.
    public func exercises(
        of workout: Workout,
        in list: ExerciseList,
    ) -> [(exercise: LoggedExercise, change: Change)] {
        let before = workouts.filter { ($0.endedAt ?? .distantFuture) < workout.startedAt }
        var earlier: [String: TopSet] = [:]
        // Oldest first, so the newest before wins.
        for previous in before.reversed() {
            for exercise in previous.loggedExercises(in: list) {
                earlier[exercise.id] = exercise.topSet
            }
        }
        return workout.loggedExercises(in: list).map { exercise in
            (exercise, exercise.topSet.change(from: earlier[exercise.id]))
        }
    }

    /// How many days before `now` the workout finished, in `calendar`'s days.
    static func daysAgo(_ workout: Workout, now: Date, calendar: Calendar) -> Int {
        let end = calendar.startOfDay(for: workout.endedAt ?? now)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: end, to: today).day ?? 0
    }

    /// The workouts finished in the last `days` days, newest first.
    func within(days: Int, of now: Date, calendar: Calendar) -> [Workout] {
        workouts.filter { Self.daysAgo($0, now: now, calendar: calendar) < days }
    }

    /// Every exercise in the workouts, by id, with its top set in each, oldest workout first, and
    /// the name the newest logged it with.
    func history(of workouts: [Workout], in list: ExerciseList) -> [ExerciseHistory] {
        var order: [String] = []
        var byID: [String: ExerciseHistory] = [:]
        for workout in workouts.reversed() {
            for exercise in workout.loggedExercises(in: list) {
                if byID[exercise.id] == nil {
                    order.append(exercise.id)
                    byID[exercise.id] = ExerciseHistory(
                        id: exercise.id,
                        name: exercise.name,
                        exercise: exercise.exercise,
                        isPerSide: exercise.isPerSide,
                    )
                }
                byID[exercise.id]?.name = exercise.name
                byID[exercise.id]?.topSets.append(exercise.topSet)
                byID[exercise.id]?.lastDone = workout.endedAt ?? .distantPast
            }
        }
        return order.compactMap { byID[$0] }
    }
}

/// One exercise across several workouts.
struct ExerciseHistory {
    let id: String
    var name: String
    let exercise: Exercise?
    let isPerSide: Bool
    /// Oldest workout first.
    var topSets: [TopSet] = []
    var lastDone = Date.distantPast
}

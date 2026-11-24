import Foundation

/// The record of finished logged workouts, newest first, and its readings: an opened logged
/// workout's exercises against the time before, the diff over the period (`LogPeriod`), and what
/// has been left alone. Days are calendar days, and a logged workout's day is the one it started
/// on, as its row reads: it is `n` days ago when `n` days lie between the start of that day and
/// the start of today.
public struct WorkoutLog: Equatable, Sendable {
    /// Finished logged workouts, the latest finish first.
    public let loggedWorkouts: [LoggedWorkout]

    public init(loggedWorkouts: [LoggedWorkout]) {
        self.loggedWorkouts = loggedWorkouts
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

    /// The log without `id`'s logged workout, as History shows it until a workout just finished
    /// comes in; the whole log with none.
    public func leavingOut(_ id: LoggedWorkout.ID?) -> Self {
        guard let id else { return self }
        return Self(loggedWorkouts: loggedWorkouts.filter { $0.id != id })
    }

    public func loggedWorkout(id: LoggedWorkout.ID) -> LoggedWorkout? {
        loggedWorkouts.first { $0.id == id }
    }

    /// The logged workout's exercises in the order done, each with the change from the newest
    /// logged workout that finished before this one started and has a set of the same exercise.
    public func exercises(
        of loggedWorkout: LoggedWorkout,
        in list: ExerciseList,
    ) -> [(exercise: LoggedExercise, change: Change)] {
        let before = loggedWorkouts.filter {
            ($0.endedAt ?? .distantFuture) < loggedWorkout.startedAt
        }
        var earlier: [String: TopSet] = [:]
        // Oldest first, so the newest before wins.
        for previous in before.reversed() {
            for exercise in previous.loggedExercises(in: list) {
                earlier[exercise.id] = exercise.topSet
            }
        }
        return loggedWorkout.loggedExercises(in: list).map { exercise in
            (exercise, exercise.topSet.change(from: earlier[exercise.id]))
        }
    }

    /// How many days before `now` the logged workout started, in `calendar`'s days.
    static func daysAgo(_ loggedWorkout: LoggedWorkout, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: loggedWorkout.startedAt)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    /// The logged workouts started in the period around `now`, newest first.
    func inPeriod(now: Date, calendar: Calendar) -> [LoggedWorkout] {
        let firstDay = LogPeriod.firstDay(calendar: calendar, now: now)
        // Bounded by `now` as History's count and calendar are (`LogPeriod`).
        return loggedWorkouts.filter { $0.startedAt >= firstDay && $0.startedAt <= now }
    }

    /// The period around `now`, with the days a logged workout started on.
    public func period(now: Date, calendar: Calendar) -> LogPeriod {
        LogPeriod(loggedWorkouts: loggedWorkouts, calendar: calendar, now: now)
    }

    /// Every exercise in the logged workouts, by id, with its top set in each, oldest logged
    /// workout first, and the name and sides the newest logged it with.
    func history(of loggedWorkouts: [LoggedWorkout], in list: ExerciseList) -> [ExerciseHistory] {
        var order: [String] = []
        var byID: [String: ExerciseHistory] = [:]
        for loggedWorkout in loggedWorkouts.reversed() {
            for exercise in loggedWorkout.loggedExercises(in: list) {
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
                byID[exercise.id]?.isPerSide = exercise.isPerSide
                byID[exercise.id]?.topSets.append(exercise.topSet)
                byID[exercise.id]?.lastDone = loggedWorkout.endedAt ?? .distantPast
            }
        }
        return order.compactMap { byID[$0] }
    }
}

/// One exercise across several logged workouts.
struct ExerciseHistory {
    let id: String
    var name: String
    let exercise: Exercise?
    /// As the newest logged it, as `name` is.
    var isPerSide: Bool
    /// Oldest logged workout first.
    var topSets: [TopSet] = []
    var lastDone = Date.distantPast
}

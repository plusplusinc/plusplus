import Foundation

/// The record of finished workout sessions, newest first, and its readings: an opened workout
/// session's exercises against the time before, the diff over the period (`LogPeriod`), and what
/// has been left alone. Days are calendar days, and a workout session's day is the one it started
/// on, as its row reads: it is `n` days ago when `n` days lie between the start of that day and
/// the start of today.
public struct WorkoutLog: Equatable, Sendable {
    /// Finished workout sessions, the latest finish first.
    public let workoutSessions: [WorkoutSession]

    public init(workoutSessions: [WorkoutSession]) {
        self.workoutSessions = workoutSessions
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

    /// The log without `id`'s workout session, as History shows it until a workout just finished
    /// comes in; the whole log with none.
    public func leavingOut(_ id: WorkoutSession.ID?) -> Self {
        guard let id else { return self }
        return Self(workoutSessions: workoutSessions.filter { $0.id != id })
    }

    public func workoutSession(id: WorkoutSession.ID) -> WorkoutSession? {
        workoutSessions.first { $0.id == id }
    }

    /// The workout session's exercises in the order done, each with the change from the newest
    /// workout session that finished before this one started and has a set of the same exercise.
    public func exercises(
        of workoutSession: WorkoutSession,
        in list: ExerciseList,
    ) -> [(exercise: LoggedExercise, change: Change)] {
        let before = workoutSessions.filter {
            ($0.endedAt ?? .distantFuture) < workoutSession.startedAt
        }
        var earlier: [String: TopSet] = [:]
        // Oldest first, so the newest before wins.
        for previous in before.reversed() {
            for exercise in previous.loggedExercises(in: list) {
                earlier[exercise.id] = exercise.topSet
            }
        }
        return workoutSession.loggedExercises(in: list).map { exercise in
            (exercise, exercise.topSet.change(from: earlier[exercise.id]))
        }
    }

    /// How many days before `now` the workout session started, in `calendar`'s days.
    static func daysAgo(_ workoutSession: WorkoutSession, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: workoutSession.startedAt)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    /// The workout sessions started in the period around `now`, newest first.
    func inPeriod(now: Date, calendar: Calendar) -> [WorkoutSession] {
        let firstDay = LogPeriod.firstDay(calendar: calendar, now: now)
        // Bounded by `now` as History's count and calendar are (`LogPeriod`).
        return workoutSessions.filter { $0.startedAt >= firstDay && $0.startedAt <= now }
    }

    /// The period around `now`, with the days a workout session started on.
    public func period(now: Date, calendar: Calendar) -> LogPeriod {
        LogPeriod(workoutSessions: workoutSessions, calendar: calendar, now: now)
    }

    /// Every exercise in the workout sessions, by id, with its top set in each, oldest workout
    /// session first, and the name and sides the newest logged it with.
    func history(of workoutSessions: [WorkoutSession], in list: ExerciseList) -> [ExerciseHistory] {
        var order: [String] = []
        var byID: [String: ExerciseHistory] = [:]
        for workoutSession in workoutSessions.reversed() {
            for exercise in workoutSession.loggedExercises(in: list) {
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
                byID[exercise.id]?.lastDone = workoutSession.endedAt ?? .distantPast
            }
        }
        return order.compactMap { byID[$0] }
    }
}

/// One exercise across several workout sessions.
struct ExerciseHistory {
    let id: String
    var name: String
    let exercise: Exercise?
    /// As the newest logged it, as `name` is.
    var isPerSide: Bool
    /// Oldest workout session first.
    var topSets: [TopSet] = []
    var lastDone = Date.distantPast
}

#if DEBUG
import Foundation
import WorkoutStore

extension LaunchOptions {
    /// `-seedLog YES`, with `resetsStore`: about ten finished workouts over five weeks back from
    /// now, covering every state Log draws: a gain in weight, reps, and time, a drop, an exercise
    /// the same in four workouts, a first time, a pair's weight, a timed set logged short and one
    /// with its sides apart, a group last worked 16 days ago and one never, a workout outside
    /// every window, one under no name, and a set of an exercise nothing resolves.
    static var seedsLog: Bool {
        UserDefaults.standard.bool(forKey: "seedLog")
    }

    static func seedLog(_ store: RoutineStore) async throws {
        for loggedWorkout in LogSeed.loggedWorkouts(now: .now) {
            try await store.save(loggedWorkout)
        }
    }
}

/// The finished logged workouts `-seedLog` saves.
private enum LogSeed {
    /// What one set is, as done and as planned.
    struct Done {
        let target: SetTarget
        var weight: Double?
        var planned: SetTarget?
        var side: Side?
    }

    static func reps(_ reps: Int, _ pounds: Double? = nil) -> Done {
        Done(target: .reps(reps), weight: pounds)
    }

    static func time(_ seconds: Int, planned: Int? = nil, side: Side? = nil) -> Done {
        Done(
            target: .time(seconds: seconds),
            planned: planned.map { .time(seconds: $0) },
            side: side,
        )
    }

    /// A routine name, days ago, minutes long, and each exercise's sets in order, by id; an id no
    /// exercise has is logged under `orphanName`.
    static func loggedWorkouts(now: Date) -> [LoggedWorkout] {
        let bench = "dumbbell-bench-press"
        let orphan = "landmine-press-retired"
        return [
            loggedWorkout("Upper body", daysAgo: 0, minutes: 51, now: now, [
                (bench, [reps(10, 30), reps(10, 30), reps(10, 30)]),
                ("pull-up", [reps(8), reps(8), reps(7)]),
                ("chin-up", [reps(6), reps(6)]),
                ("plank", [time(60), time(60), time(48, planned: 60)]),
                (orphan, [reps(8, 45), reps(8, 45)]),
            ]),
            loggedWorkout("Legs and core", daysAgo: 2, minutes: 44, now: now, [
                ("barbell-back-squat", [reps(5, 185), reps(5, 185), reps(5, 185)]),
                ("goblet-squat", [reps(10, 50), reps(10, 50)]),
                ("side-plank", [
                    time(45, side: .left), time(45, side: .right),
                    time(40, planned: 45, side: .left), time(45, side: .right),
                ]),
            ]),
            loggedWorkout("Upper body", daysAgo: 4, minutes: 48, now: now, [
                (bench, [reps(10, 25), reps(10, 25), reps(10, 25)]),
                ("pull-up", [reps(6), reps(6), reps(6)]),
                ("plank", [time(45), time(45), time(45)]),
                ("barbell-bench-press", [reps(5, 135), reps(5, 135)]),
                (orphan, [reps(8, 40), reps(8, 40)]),
            ]),
            loggedWorkout("Legs and core", daysAgo: 7, minutes: 39, now: now, [
                ("barbell-back-squat", [reps(5, 185), reps(5, 185), reps(5, 185)]),
                ("romanian-deadlift", [reps(8, 40), reps(8, 40)]),
            ]),
            loggedWorkout("", daysAgo: 9, minutes: 22, now: now, [
                ("barbell-bench-press", [reps(5, 145), reps(5, 145)]),
            ]),
            loggedWorkout("Leg day, before its rename", daysAgo: 11, minutes: 41, now: now, [
                ("barbell-back-squat", [reps(5, 185), reps(5, 185), reps(5, 185)]),
                ("romanian-deadlift", [reps(8, 40), reps(8, 40)]),
            ]),
            loggedWorkout("Upper body", daysAgo: 14, minutes: 50, now: now, [
                (bench, [reps(10, 25), reps(10, 25), reps(10, 25)]),
                ("pull-up", [reps(6), reps(6), reps(5)]),
                ("plank", [time(45), time(45), time(45)]),
            ]),
            loggedWorkout("Arms", daysAgo: 16, minutes: 27, now: now, [
                ("biceps-curl", [reps(10, 20), reps(10, 20), reps(10, 20)]),
            ]),
            loggedWorkout("Legs and core", daysAgo: 20, minutes: 43, now: now, [
                ("barbell-back-squat", [reps(5, 185), reps(5, 185), reps(5, 185)]),
            ]),
            loggedWorkout("Upper body", daysAgo: 36, minutes: 55, now: now, [
                (bench, [reps(10, 20), reps(10, 20), reps(10, 20)]),
            ]),
        ]
    }

    static let orphanName = "Half-kneeling single-arm landmine press with rotation"

    private static func loggedWorkout(
        _ name: String,
        daysAgo: Int,
        minutes: Int,
        now: Date,
        _ exercises: [(id: String, sets: [Done])],
    ) -> LoggedWorkout {
        let end = now.addingTimeInterval(-Double(daysAgo) * 86400 - 3600)
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        var sets: [LoggedSet] = []
        for (id, done) in exercises {
            let exercise = Exercise.builtIn(id: id)
            let row = UUID()
            var round = 0
            for set in done {
                if set.side != .right {
                    round += 1
                }
                let weight = set.weight.map { Weight($0, .pounds) }
                sets.append(LoggedSet(
                    row: row,
                    exerciseID: id,
                    exerciseName: exercise?.name ?? orphanName,
                    round: round,
                    side: set.side,
                    target: set.target,
                    weight: weight,
                    plannedTarget: set.planned ?? set.target,
                    plannedWeight: weight,
                    loggedAt: start.addingTimeInterval(Double(sets.count + 1) * 60),
                ))
            }
        }
        return LoggedWorkout(
            routineID: UUID(),
            routineName: name,
            startedAt: start,
            endedAt: end,
            sets: sets,
        )
    }
}
#endif

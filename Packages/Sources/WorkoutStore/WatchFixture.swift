#if DEBUG
import Foundation

/// Fixed workouts in progress, one per frame of the Watch's boards, for its screenshots
/// (`-watchState`) and `WatchFaceTests`. Each is reached through the rules a person's taps
/// run (`landingStart`, `beginningCount`, `logging`, `pausing`), so it is a state the app can
/// be in. Debug only.
public enum WatchFixture: String, CaseIterable, Sendable {
    case startIn
    case set
    case resting
    case allLogged
    case timed
    case perSide
    case superset
    case paused
    case unreachable

    /// The moment every fixture is read at, fixed so a screenshot is the same each time.
    public static let start = Date(timeIntervalSinceReferenceDate: 820_000_000)

    /// The workout as the fixture holds it, and the moment it is shown at.
    public var live: (live: LiveWorkout, at: Date) {
        switch self {
        case .startIn: Self.run(Self.benchWorkout, sets: 0, then: 0)
        case .set, .unreachable: Self.run(Self.benchWorkout, sets: 0, then: 6)
        case .resting: Self.run(Self.benchWorkout, sets: 1, then: 32)
        case .allLogged: Self.run(Self.pushDayWorkout, sets: 9, then: 1)
        case .timed: Self.run(Self.plankWorkout, sets: 0, then: 24)
        case .perSide: Self.run(Self.rowWorkout, sets: 2, then: 70)
        case .superset: Self.run(Self.supersetWorkout, sets: 2, then: 40)
        case .paused: Self.pausedOnSecondSet
        }
    }

    /// A workout to run on the Watch alone, from Start: a set, a set done a side at a time, a
    /// timed set, and a superset.
    public static var demo: Workout {
        Workout(name: "Watch demo", exercises: [
            row("barbell-bench-press", sets: 2, .reps(5), Weight(45, .pounds), rest: 20),
            row("dumbbell-row", sets: 2, .reps(10), Weight(25, .pounds), rest: 15),
            row("plank", sets: 1, .time(seconds: 20), nil, rest: 15),
        ] + supersetRows(sets: 2))
    }

    // MARK: The workouts

    static let benchWorkout = Workout(name: "Push day", exercises: [
        row("barbell-bench-press", sets: 3, .reps(5), Weight(45, .pounds), rest: 60),
    ])

    static let pushDayWorkout = Workout(name: "Push day", exercises: [
        row("barbell-bench-press", sets: 3, .reps(5), Weight(45, .pounds), rest: 60),
        row("push-up", sets: 3, .reps(12), nil, rest: 45),
        row("pull-up", sets: 3, .reps(6), nil, rest: 60),
    ])

    static let plankWorkout = Workout(name: "Core", exercises: [
        row("plank", sets: 3, .time(seconds: 60), nil, rest: 30),
    ])

    static let rowWorkout = Workout(name: "Pull day", exercises: [
        row("dumbbell-row", sets: 3, .reps(10), Weight(25, .pounds), rest: 60),
    ])

    static let supersetWorkout = Workout(name: "Upper body", exercises: supersetRows(sets: 3))

    private static func supersetRows(sets: Int) -> [WorkoutExercise] {
        let group = UUID()
        return [
            WorkoutExercise(
                exercise: exercise("push-up"),
                plan: ExercisePlan(sets: sets, target: .reps(12), rest: .byHand(0)),
                supersetID: group,
                roundRest: .byHand(30),
            ),
            WorkoutExercise(
                exercise: exercise("pull-up"),
                plan: ExercisePlan(sets: sets, target: .reps(6), rest: .byHand(0)),
                supersetID: group,
                roundRest: .byHand(30),
            ),
        ]
    }

    private static func row(
        _ id: String,
        sets: Int,
        _ target: SetTarget,
        _ weight: Weight?,
        rest: Int,
    ) -> WorkoutExercise {
        WorkoutExercise(
            exercise: exercise(id),
            plan: ExercisePlan(sets: sets, target: target, weight: weight, rest: .byHand(rest)),
        )
    }

    private static func exercise(_ id: String) -> Exercise {
        guard let exercise = Exercise.builtIn(id: id) else {
            preconditionFailure("No built-in exercise \(id)")
        }
        return exercise
    }

    // MARK: Running them

    /// Starts `workout` at `start`, logs its first `sets` sets as a person would, each once its
    /// count and the rest before it are over, then waits `then` seconds after the last log (or
    /// after Start).
    static func run(_ workout: Workout, sets: Int, then: Double) -> (LiveWorkout, Date) {
        var now = start
        var live = LiveWorkout(
            workout: workout,
            workoutSession: WorkoutSession(
                workoutID: workout.id,
                workoutName: workout.name,
                startedAt: now,
            ),
        )
        live.workoutSession = live.landingStart(at: now)
        for done in 0 ..< sets {
            if done > 0 {
                now = afterRest(live, from: now)
            }
            live.workoutSession = live.beginningCount(at: now)
            if let count = live.setCount {
                now = max(now, live.workoutSession.date(ofClock: count.startClock))
            }
            now += 3
            guard let set = live.currentSet, let item = live.currentExercise else { break }
            live.workoutSession = live.logging(set, of: item, at: now)
        }
        return (live, now + then)
    }

    /// Past the rest after the last log, if there is one, else `now`.
    private static func afterRest(_ live: LiveWorkout, from now: Date) -> Date {
        live.rest().map { live.workoutSession.date(ofClock: $0.leaveClock) + 0.5 } ?? now
    }

    /// Bench's second set, paused a few seconds in.
    private static var pausedOnSecondSet: (LiveWorkout, Date) {
        var (live, now) = run(benchWorkout, sets: 1, then: 0)
        now = afterRest(live, from: now)
        live.workoutSession = live.beginningCount(at: now)
        live.workoutSession = live.workoutSession.pausing(at: now + 8)
        return (live, now + 20)
    }
}
#endif

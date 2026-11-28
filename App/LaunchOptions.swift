#if DEBUG
import Foundation
import WorkoutStore

/// Launch arguments the UI tests pass, as `-name YES` or `-name value`. Compiled out of release
/// builds.
enum LaunchOptions {
    /// Start from an empty store.
    static var resetsStore: Bool {
        UserDefaults.standard.bool(forKey: "resetStore")
    }

    /// Name workouts from their muscle groups alone. A workout's style follows its id, so a test
    /// can't predict the standard name of a workout it just made; the muscle-group names are the
    /// same for every workout.
    static var usesFallbackNames: Bool {
        UserDefaults.standard.bool(forKey: "fallbackNames")
    }

    /// Run UIKit's animations, such as the keyboard rising and a sheet sliding up, without
    /// motion. XCTest waits after every action until it has seen each UIKit animation it saw
    /// start also stop. On a keyboard rise or a sheet, UIKit sometimes reports one animation's
    /// start twice and its stop once, and every later wait in that launch then runs out its 60 s.
    /// With no UIKit animations there is nothing to miscount. SwiftUI's own animations still run.
    static var turnsOffUIKitAnimations: Bool {
        UserDefaults.standard.bool(forKey: "noUIKitAnimations")
    }

    /// `-seedRest <seconds>`: every rest after a set lasts this long, in place of the workout's,
    /// so the UI tests, launched with 0, log on with no rest between exercises. Read once, at
    /// launch, into `LiveWorkout.overrideRests(with:)`.
    static var restOverride: Int? {
        UserDefaults.standard.object(forKey: "seedRest").flatMap { _ in
            UserDefaults.standard.integer(forKey: "seedRest")
        }
    }

    /// With `resetsStore`, a workout to launch into in place of a new one: `-seedExercises`
    /// lists built-in exercise ids, comma-separated, and `-seedName` names it. A test that needs
    /// rows but doesn't check adding them starts with them, rather than spending seconds an add
    /// in the picker.
    /// `-seedSuperset` joins the seeded rows from one index to another, from 0, into a
    /// superset ("1,2"), for a workout to step through one.
    /// `-seedSets` gives every seeded row that many sets, for a test that needs fewer logs to
    /// reach a workout's end. `-seedWorkout <n>` also starts the seeded workout, with its
    /// first `n` sets logged as taps would, so the app opens mid-workout through the relaunch
    /// path, on the next set: none of them starts a rest.
    static var seededWorkout: SeededWorkout? {
        let defaults = UserDefaults.standard
        guard let ids = defaults.string(forKey: "seedExercises") else { return nil }
        let ends = defaults.string(forKey: "seedSuperset")?
            .split(separator: ",").compactMap { Int($0) } ?? []
        return SeededWorkout(
            name: defaults.string(forKey: "seedName") ?? "",
            exercises: ids.split(separator: ",").compactMap { Exercise.builtIn(id: String($0)) },
            superset: ends.count == 2 && ends[0] < ends[1] ? ends[0] ... ends[1] : nil,
            // At least a set per row, and no fewer than none logged.
            sets: defaults.string(forKey: "seedSets").flatMap { Int($0) }.map { max($0, 1) },
            loggedSets: defaults.string(forKey: "seedWorkout").flatMap { Int($0) }
                .map { max($0, 0) },
            time: defaults.string(forKey: "seedTime").flatMap { Int($0) }.map { max($0, 1) },
        )
    }

    /// Empties the store, then saves the workout and the logged workout the launch arguments ask
    /// for.
    static func resetStore(
        _ store: Store,
        weightUnit: WeightUnit,
        namer: WorkoutNamer,
    ) async throws {
        try await store.deleteAll()
        if seedsLog {
            try await seedLog(store)
        }
        if seedsWorkouts {
            try await seedWorkouts(store, weightUnit: weightUnit)
        }
        guard let seed = seededWorkout else { return }
        let workout = seed.workout(weightUnit: weightUnit)
        try await store.save(workout)
        guard let logged = seed.loggedSets else { return }
        var workoutSession = WorkoutSession(
            workoutID: workout.id,
            workoutName: namer.shownName(of: workout) ?? "",
            startedAt: .now,
        )
        for set in workout.setOrder.prefix(logged) {
            if let row = workout.exercises.first(where: { $0.id == set.row }) {
                workoutSession = workoutSession.logging(set, of: row, at: .now)
            }
        }
        // Logged with no time kept, as before a rest's was: the workout opens on its next set,
        // not in the rest after the last one seeded.
        for index in workoutSession.sets.indices {
            workoutSession.sets[index].clockWhenLogged = nil
        }
        try await store.save(workoutSession)
    }
}

/// The workout, and the logged workout on it, that `-seedExercises`, `-seedName`,
/// `-seedSuperset`, `-seedSets`, and `-seedWorkout` ask for.
struct SeededWorkout {
    let name: String
    let exercises: [Exercise]
    /// The rows joined into a superset, by index from 0.
    let superset: ClosedRange<Int>?
    /// Every row's sets, in place of its exercise's default.
    let sets: Int?
    /// With a workout in progress, how many of its sets are logged.
    let loggedSets: Int?
    /// `-seedTime <seconds>`: every timed row's time, so a timed set runs out in seconds.
    let time: Int?

    func workout(weightUnit: WeightUnit) -> Workout {
        var workout = Workout(
            name: name,
            exercises: exercises.map { exercise in
                var row = WorkoutExercise(exercise: exercise, weightUnit: weightUnit)
                if let sets {
                    row.plan.sets = sets
                }
                if let time, case .time = row.plan.target {
                    row.plan.target = .time(seconds: time)
                }
                return row
            },
        )
        if let superset {
            for index in superset.dropLast() where workout.exercises.indices.contains(index + 1) {
                workout.join(workout.exercises[index].id, .below)
            }
        }
        return workout
    }
}
#endif

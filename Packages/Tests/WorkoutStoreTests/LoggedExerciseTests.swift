import Foundation
import Testing
@testable import WorkoutStore

@Suite("An exercise as a workout did it")
struct LoggedExerciseTests {
    private typealias Fixture = LogFixture

    @Test("Sets group by exercise in the order first logged, a superset's included")
    func groupsInOrder() {
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 0, [
            Fixture.set("pull-up", round: 1, .reps(6)),
            Fixture.set("plank", round: 1, .time(seconds: 30)),
            Fixture.set("pull-up", round: 2, .reps(6)),
            Fixture.set("plank", round: 2, .time(seconds: 30)),
        ])
        let exercises = loggedWorkout.loggedExercises(in: .builtIn)
        #expect(exercises.map(\.id) == ["pull-up", "plank"])
        #expect(exercises.map(\.rounds.count) == [2, 2])
    }

    @Test("An opened workout's change is from the newest workout finished before it began")
    func changeFromTimeBefore() {
        let oldest = Fixture.loggedWorkout(daysAgo: 6, [Fixture.set("pull-up", .reps(4))])
        let before = Fixture.loggedWorkout(daysAgo: 4, [Fixture.set("pull-up", .reps(6))])
        let opened = Fixture.loggedWorkout(daysAgo: 2, [
            Fixture.set("pull-up", .reps(8)),
            Fixture.set("plank", .time(seconds: 30)),
        ])
        let after = Fixture.loggedWorkout(daysAgo: 0, [Fixture.set("pull-up", .reps(10))])
        let log = WorkoutLog(loggedWorkouts: [oldest, after, opened, before])
        let rows = log.exercises(of: opened, in: .builtIn)
        #expect(rows.map(\.exercise.id) == ["pull-up", "plank"])
        #expect(rows.map(\.change) == [.up(.reps(2, withWeight: false)), .first])
    }

    @Test("One exercise in two rows reads once, with both rows' rounds")
    func twoRowsReadOnce() {
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 0, [
            Fixture.set("pull-up", round: 1, .reps(6), row: UUID()),
            Fixture.set("pull-up", round: 1, .reps(5), row: UUID()),
        ])
        let exercises = loggedWorkout.loggedExercises(in: .builtIn)
        #expect(exercises.count == 1)
        #expect(exercises[0].rounds.count == 2)
    }

    @Test("Left and right of a round are one round, counted as the lesser side")
    func sidesAreOneRound() {
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 0, [
            Fixture.set("side-plank", .time(seconds: 30), side: .left),
            Fixture.set(
                "side-plank",
                .time(seconds: 24),
                planned: .time(seconds: 30),
                side: .right,
            ),
        ])
        let exercise = loggedWorkout.loggedExercises(in: .builtIn)[0]
        #expect(exercise.rounds.count == 1)
        #expect(exercise.rounds[0].counted.target == .time(seconds: 24))
        #expect(exercise.isPerSide)
        #expect(exercise.rounds[0].isShort)
    }

    @Test("A name is the logged one, else the exercise's now, else the fallback")
    func names() {
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 0, [
            Fixture.set("pull-up", .reps(6), name: "Pull-ups, old name"),
            Fixture.set("plank", .reps(6), name: nil),
            Fixture.set("gone", .reps(6), name: nil),
        ])
        let names = loggedWorkout.loggedExercises(in: .builtIn).map(\.name)
        #expect(names == ["Pull-ups, old name", "Plank", "Exercise"])
    }
}

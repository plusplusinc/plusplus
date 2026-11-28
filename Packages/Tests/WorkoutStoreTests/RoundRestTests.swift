import Foundation
import Testing
@testable import WorkoutStore

/// A superset's one rest after each round, shared by its members.
@Suite("Superset rest")
struct RoundRestTests {
    /// The rows named, the first two joined into a superset.
    private static func joined(_ names: String...) throws -> Workout {
        var workout = try Workout(exercises: names.map { try WorkoutExercise.builtIn($0) })
        workout.join(workout.exercises[0].id, .below)
        return workout
    }

    @Test("A superset rests its longest member's rest less 60 s, never under 30 s")
    func derived() throws {
        // Bench press 90 s and dumbbell row 90 s, no primary muscle shared: 30 s.
        let press = try Self.joined("Dumbbell bench press", "Dumbbell row")
        #expect(press.restAfterRound(of: press.exercises[0].id) == 30)
        // Barbell bench 150 s and dumbbell row 90 s: 90 s.
        let heavy = try Self.joined("Barbell bench press", "Dumbbell row")
        #expect(heavy.restAfterRound(of: heavy.exercises[1].id) == 90)
        // Two stretches rest none, never the 30 s floor.
        let stretches = try Self.joined("Pigeon stretch", "Hamstring stretch")
        #expect(stretches.restAfterRound(of: stretches.exercises[0].id) == 0)
        #expect(press.isRoundAuto(of: press.exercises[0].id))
    }

    @Test("Members sharing a primary muscle rest the longest member's full rest")
    func sharedMuscle() throws {
        let legs = try Self.joined("Barbell back squat", "Reverse lunge")
        #expect(legs.restAfterRound(of: legs.exercises[1].id) == 180)
    }

    @Test("A plain row has no superset rest")
    func plain() throws {
        let workout = try Self.joined("Push-up", "Plank", "Dumbbell row")
        let plain = workout.exercises[2].id
        #expect(workout.restAfterRound(of: plain) == nil)
        #expect(workout.restAfterRoundText(of: plain).isEmpty)
        #expect(!workout.isRoundAuto(of: plain))
    }

    @Test("Stepping one member's rest steps every member's, 15 s, and turns Auto off")
    func shared() throws {
        var workout = try Self.joined("Barbell bench press", "Dumbbell row")
        let (first, second) = (workout.exercises[0].id, workout.exercises[1].id)
        workout.stepRestAfterRound(of: first, by: .up)
        #expect(workout.restAfterRound(of: second) == 105)
        #expect(!workout.isRoundAuto(of: second))
        #expect(workout.restAfterRoundText(of: second, locale: Locale(identifier: "en_US"))
            == "1m\u{00A0}45s")
        // A member's own reps no longer move a rest set by hand.
        var bench = workout.exercises[0]
        for _ in 0 ..< 10 {
            bench.step(.target, by: .up)
        }
        workout.update(bench)
        #expect(workout.restAfterRound(of: first) == 105)
    }

    @Test("A row written back with new rounds keeps its superset's rest, whatever rest it carries")
    func updateKeepsRoundRest() throws {
        var workout = try Self.joined("Barbell bench press", "Dumbbell row")
        let (first, second) = (workout.exercises[0].id, workout.exercises[1].id)
        workout.stepRestAfterRound(of: first, by: .up)
        var bench = workout.exercises[0]
        bench.roundRest = .neverSet
        bench.plan.sets += 1
        workout.update(bench)
        #expect(workout.exercises.map(\.plan.sets) == [bench.plan.sets, bench.plan.sets])
        #expect(workout.restAfterRound(of: first) == 105)
        #expect(!workout.isRoundAuto(of: second))
    }

    @Test("Auto on derives the rest again; off brings back the one set by hand, on every member")
    func autoRemembers() throws {
        var workout = try Self.joined("Barbell bench press", "Dumbbell row")
        let (first, second) = (workout.exercises[0].id, workout.exercises[1].id)
        workout.stepRestAfterRound(of: first, by: .down)
        #expect(workout.restAfterRound(of: first) == 75)
        workout.setRoundAuto(true, of: second)
        #expect(workout.isRoundAuto(of: first))
        #expect(workout.restAfterRound(of: first) == 90)
        workout.setRoundAuto(false, of: first)
        #expect(workout.restAfterRound(of: second) == 75)
    }

    @Test("Auto turned off before any rest was set keeps the rest it reads")
    func autoOffKeepsReading() throws {
        var workout = try Self.joined("Barbell bench press", "Dumbbell row")
        let first = workout.exercises[0].id
        workout.setRoundAuto(false, of: first)
        #expect(workout.restAfterRound(of: first) == 90)
        var bench = workout.exercises[0]
        for _ in 0 ..< 10 {
            bench.step(.target, by: .up)
        }
        workout.update(bench)
        #expect(workout.restAfterRound(of: first) == 90)
    }

    @Test("Joining keeps each row's own rest; splitting brings it back, the superset's gone")
    func splitRestores() throws {
        var workout = try Workout(exercises: [
            WorkoutExercise.builtIn("Barbell bench press") {
                $0.rest = .byHand(200)
            },
            WorkoutExercise.builtIn("Dumbbell row"),
        ])
        let (first, second) = (workout.exercises[0].id, workout.exercises[1].id)
        workout.join(first, .below)
        workout.stepRestAfterRound(of: first, by: .up)
        #expect(workout.exercises.map(\.rest) == [200, 90])
        workout.leaveSuperset(second)
        #expect(workout.exercises.map(\.rest) == [200, 90])
        #expect(workout.exercises.allSatisfy { $0.roundRest == .neverSet })
        #expect(workout.restAfterRound(of: first) == nil)
    }

    @Test("A row joining a superset takes its rest set by hand; a superset set by hand wins a join")
    func joinTakesSetRest() throws {
        var workout = try Self.joined("Barbell bench press", "Dumbbell row", "Biceps curl")
        let (first, third) = (workout.exercises[0].id, workout.exercises[2].id)
        workout.stepRestAfterRound(of: first, by: .up)
        workout.join(third, .above)
        #expect(workout.restAfterRound(of: third) == 105)
        #expect(!workout.isRoundAuto(of: third))
    }
}

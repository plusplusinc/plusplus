import Foundation
import Testing
@testable import WorkoutStore

/// A superset's one rest after each round, shared by its members.
@Suite("Superset rest")
struct RoundRestTests {
    /// The rows named, the first two joined into a superset.
    private static func joined(_ names: String...) throws -> Routine {
        var routine = try Routine(exercises: names.map { try RoutineExercise.builtIn($0) })
        routine.join(routine.exercises[0].id, .below)
        return routine
    }

    @Test("A superset rests its longest member's rest less 60 s, never under 30 s")
    func derived() throws {
        // Bench press 90 s and dumbbell row 90 s, no primary muscle shared: 30 s.
        let press = try Self.joined("Dumbbell bench press", "Dumbbell row")
        #expect(press.roundValue(.afterRound, of: press.exercises[0].id) == 30)
        // Barbell bench 150 s and dumbbell row 90 s: 90 s.
        let heavy = try Self.joined("Barbell bench press", "Dumbbell row")
        #expect(heavy.roundValue(.afterRound, of: heavy.exercises[1].id) == 90)
        // Two stretches rest none, never the 30 s floor.
        let stretches = try Self.joined("Pigeon stretch", "Hamstring stretch")
        #expect(stretches.roundValue(.afterRound, of: stretches.exercises[0].id) == 0)
        #expect(press.isRoundAuto(of: press.exercises[0].id))
    }

    @Test("Members sharing a primary muscle rest the longest member's full rest")
    func sharedMuscle() throws {
        let legs = try Self.joined("Barbell back squat", "Reverse lunge")
        #expect(legs.roundValue(.afterRound, of: legs.exercises[1].id) == 180)
    }

    @Test("A plain row has no superset rest")
    func plain() throws {
        let routine = try Self.joined("Push-up", "Plank", "Dumbbell row")
        let plain = routine.exercises[2].id
        #expect(routine.roundValue(.afterRound, of: plain) == nil)
        #expect(routine.roundText(.afterRound, of: plain).isEmpty)
        #expect(!routine.isRoundAuto(of: plain))
    }

    @Test("Stepping one member's rest steps every member's, 15 s, and turns Auto off")
    func shared() throws {
        var routine = try Self.joined("Barbell bench press", "Dumbbell row")
        let (first, second) = (routine.exercises[0].id, routine.exercises[1].id)
        routine.stepRound(.afterRound, of: first, by: 1)
        #expect(routine.roundValue(.afterRound, of: second) == 105)
        #expect(!routine.isRoundAuto(of: second))
        #expect(routine.roundText(.afterRound, of: second, locale: Locale(identifier: "en_US"))
            == "105\u{00A0}s")
        // A member's own reps no longer move a rest set by hand.
        var bench = routine.exercises[0]
        bench.step(.target, by: 10)
        routine.update(bench)
        #expect(routine.roundValue(.afterRound, of: first) == 105)
    }

    @Test("Auto on derives the rest again; off brings back the one set by hand, on every member")
    func autoRemembers() throws {
        var routine = try Self.joined("Barbell bench press", "Dumbbell row")
        let (first, second) = (routine.exercises[0].id, routine.exercises[1].id)
        routine.stepRound(.afterRound, of: first, by: -1)
        #expect(routine.roundValue(.afterRound, of: first) == 75)
        routine.setRoundAuto(true, of: second)
        #expect(routine.isRoundAuto(of: first))
        #expect(routine.roundValue(.afterRound, of: first) == 90)
        routine.setRoundAuto(false, of: first)
        #expect(routine.roundValue(.afterRound, of: second) == 75)
    }

    @Test("Auto turned off before any rest was set keeps the rest it reads")
    func autoOffKeepsReading() throws {
        var routine = try Self.joined("Barbell bench press", "Dumbbell row")
        let first = routine.exercises[0].id
        routine.setRoundAuto(false, of: first)
        #expect(routine.roundValue(.afterRound, of: first) == 90)
        var bench = routine.exercises[0]
        bench.step(.target, by: 10)
        routine.update(bench)
        #expect(routine.roundValue(.afterRound, of: first) == 90)
    }

    @Test("Joining keeps each row's own rest; splitting brings it back, the superset's gone")
    func splitRestores() throws {
        var routine = try Routine(exercises: [
            RoutineExercise.builtIn("Barbell bench press") {
                $0.rest = 200
                $0.isRestAuto = false
            },
            RoutineExercise.builtIn("Dumbbell row"),
        ])
        let (first, second) = (routine.exercises[0].id, routine.exercises[1].id)
        routine.join(first, .below)
        routine.stepRound(.afterRound, of: first, by: 1)
        #expect(routine.exercises.map(\.rest) == [200, 90])
        routine.leaveSuperset(second)
        #expect(routine.exercises.map(\.rest) == [200, 90])
        #expect(routine.exercises.allSatisfy { $0.roundRest == RoundRest() })
        #expect(routine.roundValue(.afterRound, of: first) == nil)
    }

    @Test("A row joining a superset takes its rest set by hand; a superset set by hand wins a join")
    func joinTakesSetRest() throws {
        var routine = try Self.joined("Barbell bench press", "Dumbbell row", "Biceps curl")
        let (first, third) = (routine.exercises[0].id, routine.exercises[2].id)
        routine.stepRound(.afterRound, of: first, by: 1)
        routine.join(third, .above)
        #expect(routine.roundValue(.afterRound, of: third) == 105)
        #expect(!routine.isRoundAuto(of: third))
    }
}

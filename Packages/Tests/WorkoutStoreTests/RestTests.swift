import Foundation
import Testing
@testable import WorkoutStore

/// A row's rest after each set: its default from the planned reps and the kind of exercise,
/// following the reps while automatic, and staying put once set by hand.
@Suite("Rest")
struct RestTests {
    private static let locale = Locale(identifier: "en_US")

    private static func rest(_ name: String, _ target: SetTarget) throws -> Int {
        try Exercise.builtIn(named: name).defaultRest(for: target)
    }

    @Test("Loaded lifts rest by planned reps and kind: every row of the table")
    func table() throws {
        // Lower-body compound, upper-body compound, single-joint; each loaded.
        let kinds = ["Barbell back squat", "Barbell bench press", "Biceps curl"]
        let rows: [(reps: [Int], rests: [Int])] = [
            ([1, 5], [180, 150, 120]),
            ([6, 12], [120, 90, 60]),
            ([13, 30], [90, 60, 45]),
        ]
        for (reps, rests) in rows {
            for count in reps {
                #expect(try kinds.map { try Self.rest($0, .reps(count)) } == rests, "\(count) reps")
            }
        }
    }

    @Test("Hinge and lunge rest as lower-body compounds; pull as upper; no pattern as single-joint")
    func kinds() throws {
        #expect(try Self.rest("Romanian deadlift", .reps(10)) == 120)
        #expect(try Self.rest("Reverse lunge", .reps(10)) == 120)
        #expect(try Self.rest("Dumbbell row", .reps(10)) == 90)
        #expect(try Self.rest("Lateral raise", .reps(12)) == 60)
        #expect(try Self.rest("Triceps extension", .reps(12)) == 60)
    }

    @Test("Bodyweight or a band rests one row shorter, and from the last row the next kind's")
    func bodyweightDrop() throws {
        #expect(try Self.rest("Bodyweight squat", .reps(5)) == 120)
        #expect(try Self.rest("Bodyweight squat", .reps(10)) == 90)
        #expect(try Self.rest("Bodyweight squat", .reps(15)) == 60)
        #expect(try Self.rest("Push-up", .reps(5)) == 90)
        #expect(try Self.rest("Push-up", .reps(12)) == 60)
        #expect(try Self.rest("Push-up", .reps(15)) == 45)
        #expect(try Self.rest("Band pull-apart", .reps(15)) == 45)
        #expect(try Self.rest("Band pull-apart", .reps(5)) == 60)
    }

    @Test("Pull-up, chin-up, and ring dip rest as loaded lifts, not a row shorter")
    func nearMax() throws {
        for name in ["Pull-up", "Chin-up", "Ring dip"] {
            #expect(try Self.rest(name, .reps(6)) == 90, "\(name)")
            #expect(try Self.rest(name, .reps(5)) == 150, "\(name)")
        }
        #expect(try Self.rest("Inverted row", .reps(6)) == 60)
    }

    @Test("A timed set rests as long as it works; a stretch rests none, timed or counted")
    func timedAndStretch() throws {
        #expect(try Self.rest("Plank", .time(seconds: 30)) == 30)
        #expect(try Self.rest("Plank", .time(seconds: 75)) == 75)
        // Never past the longest rest, so it stores, steps, and reopens as it reads.
        #expect(try Self.rest("Plank", .time(seconds: 900)) == 600)
        #expect(try Self.rest("Farmer\u{2019}s carry", .time(seconds: 45)) == 45)
        #expect(try Self.rest("Pigeon stretch", .time(seconds: 60)) == 0)
        #expect(try Self.rest("Cat-cow", .reps(10)) == 0)
        for exercise in Exercise.builtIn where exercise.tags.kind == .stretch {
            let target = exercise.defaultPlan(in: .pounds).target
            #expect(exercise.defaultRest(for: target) == 0, "\(exercise.name)")
        }
    }

    @Test("The card's rows read their rest, each automatic")
    func cardExamples() throws {
        let rows = try [
            RoutineExercise.builtIn("Barbell back squat"),
            RoutineExercise.builtIn("Barbell bench press") { $0.target = .reps(10) },
            RoutineExercise.builtIn("Dumbbell row"),
            RoutineExercise.builtIn("Biceps curl"),
            RoutineExercise.builtIn("Push-up"),
            RoutineExercise.builtIn("Bodyweight squat") { $0.sets = 3 },
            RoutineExercise.builtIn("Plank"),
            RoutineExercise.builtIn("Pigeon stretch"),
        ]
        #expect(rows.map { $0.value(of: .rest, locale: Self.locale) }
            .map { $0.replacingOccurrences(of: "\u{00A0}", with: " ") }
            == ["3 min", "90 s", "90 s", "60 s", "60 s", "60 s", "30 s", "None"])
        #expect(rows.allSatisfy { $0.isRestAuto })
        #expect(rows[0].spokenValue(of: .rest, locale: Self.locale) == "3 minutes")
        #expect(rows[7].spokenValue(of: .rest, locale: Self.locale) == "None")
    }

    @Test("Every row's sheet has Rest, a one-set row's and a one-round superset's too")
    func sheetParts() throws {
        var routine = try Routine(exercises: [
            RoutineExercise.builtIn("Barbell bench press"),
            RoutineExercise.builtIn("Push-up") { $0.sets = 1 },
            RoutineExercise.builtIn("Dumbbell row"),
            RoutineExercise.builtIn("Plank"),
        ])
        let ids = routine.exercises.map(\.id)
        #expect(routine.sheetParts(of: ids[0]) == [
            .plan(.sets),
            .plan(.target),
            .plan(.weight),
            .plan(.rest),
        ])
        #expect(routine.sheetParts(of: ids[1]) == [.plan(.sets), .plan(.target), .plan(.rest)])
        #expect(routine.exercises[1].label(of: .rest) == "Rest")
        routine.join(ids[2], .below)
        var row = routine.exercises[2]
        while row.canStep(.sets, by: -1) {
            row.step(.sets, by: -1)
        }
        routine.update(row)
        #expect(routine.exercises[3].plan.sets == 1)
        #expect(routine.sheetParts(of: ids[3]) == [.plan(.sets), .plan(.target), .restAfterRound])
        #expect(routine.sheetParts(of: ids[2]).last == .restAfterRound)
    }

    @Test("A rest set by hand stays through reps, the time, or both, by what its rows count")
    func restChange() throws {
        let bench = try RoutineExercise.builtIn("Barbell bench press")
        let plank = try RoutineExercise.builtIn("Plank")
        let farmer = try RoutineExercise.builtIn("Farmer\u{2019}s carry")
        #expect([bench].restChange == "reps")
        #expect([plank].restChange == "the time")
        #expect([plank, farmer].restChange == "the time")
        #expect([bench, plank].restChange == "reps or time")
    }

    @Test("While automatic, rest follows the reps and a timed set's time")
    func followsReps() throws {
        var bench = try RoutineExercise.builtIn("Barbell bench press") { $0.target = .reps(10) }
        #expect(bench.rest == 90)
        for _ in 0 ..< 5 {
            bench.step(.target, by: -1)
        }
        #expect(bench.plan.target == .reps(5))
        #expect(bench.rest == 150)
        #expect(bench.value(of: .rest, locale: Self.locale) == "2:30\u{00A0}min")
        #expect(bench.isRestAuto)

        var plank = try RoutineExercise.builtIn("Plank")
        plank.step(.target, by: 1)
        #expect(plank.rest == 35)
    }

    @Test(
        "A step sets rest by hand, 15 s at a time: Auto goes off and the rest stays as reps change",
    )
    func handSetStays() throws {
        var bench = try RoutineExercise.builtIn("Barbell bench press") { $0.target = .reps(10) }
        bench.step(.rest, by: -1)
        #expect(bench.rest == 75)
        #expect(!bench.isRestAuto)
        bench.step(.target, by: -5)
        bench.step(.target, by: -1)
        #expect(bench.rest == 75)
    }

    @Test("Auto on goes back to the reps' rest; off again brings back the rest set by hand")
    func autoRemembers() throws {
        var bench = try RoutineExercise.builtIn("Barbell bench press") { $0.target = .reps(10) }
        bench.step(.rest, by: 1)
        #expect(bench.rest == 105)
        bench.isRestAuto = true
        #expect(bench.rest == 90)
        #expect(bench.plan.rest == 105)
        bench.isRestAuto = false
        #expect(bench.rest == 105)
    }

    @Test("Auto turned off before any rest was set keeps the rest it reads")
    func autoOffKeepsReading() throws {
        var curl = try RoutineExercise.builtIn("Biceps curl")
        curl.isRestAuto = false
        #expect(curl.plan.rest == 60)
        curl.step(.target, by: -10)
        #expect(curl.rest == 60)
    }

    @Test("A rest off the 15 s marks steps to the next mark that way, then by 15 s")
    func snapsToMarks() throws {
        var plank = try RoutineExercise.builtIn("Plank") { $0.target = .time(seconds: 50) }
        #expect(plank.rest == 50)
        plank.step(.rest, by: 1)
        #expect(plank.rest == 60)
        plank.step(.rest, by: 1)
        #expect(plank.rest == 75)
        var down = try RoutineExercise.builtIn("Plank") { $0.target = .time(seconds: 50) }
        down.step(.rest, by: -1)
        #expect(down.rest == 45)
        down.step(.rest, by: -1)
        #expect(down.rest == 30)
        var near = try RoutineExercise.builtIn("Plank") { $0.target = .time(seconds: 10) }
        near.step(.rest, by: -1)
        #expect(near.rest == 0)
        #expect(!near.canStep(.rest, by: -1))
        #expect(595.steppedRest(by: 1) == 600)
        #expect(600.steppedRest(by: 1) == nil)
    }

    @Test("Rest steps stop at none and at 10 min")
    func limits() throws {
        var stretch = try RoutineExercise.builtIn("Pigeon stretch")
        #expect(!stretch.canStep(.rest, by: -1))
        #expect(stretch.canStep(.rest, by: 1))
        stretch.step(.rest, by: 1)
        #expect(stretch.rest == 15)
        var long = try RoutineExercise.builtIn("Barbell back squat") {
            $0.rest = 600
            $0.isRestAuto = false
        }
        #expect(!long.canStep(.rest, by: 1))
        long.step(.rest, by: -1)
        #expect(long.rest == 585)
        #expect(PlanLimits.rest == 0 ... 600)
    }
}

import Foundation
import Testing
@testable import WorkoutStore

/// What a ruler sets on a row, and how its open row reads while it shows: a weight anywhere in
/// its stepper's range, a timed set's time and a rest on 5 s ticks, and − / + from a value off
/// their marks landing on the next mark.
@Suite("Ruler values")
struct RulerValueTests {
    private static let english = Locale(identifier: "en_US")
    private static let german = Locale(identifier: "de_DE")

    private static func row(_ name: String, edit: (inout ExercisePlan) -> Void = { _ in })
        throws -> RoutineExercise
    {
        try RoutineExercise.builtIn(name, edit)
    }

    @Test("A weight's range is its stepper's: one step, or the empty bar, up to 1000; none without")
    func weightRange() throws {
        #expect(try Self.row("Biceps curl").weightRange == 5 ... 1000)
        #expect(try Self.row("Barbell row").weightRange == 45 ... 1000)
        let kilograms = try RoutineExercise(
            exercise: Exercise.builtIn(named: "Barbell row"),
            weightUnit: .kilograms,
        )
        #expect(kilograms.weightRange == 20 ... 1000)
        #expect(try Self.row("Push-up").weightRange == nil)
    }

    @Test("Setting a weight takes any amount in its range, held to its ends")
    func setWeight() throws {
        var curl = try Self.row("Biceps curl")
        curl.setWeight(27.5)
        #expect(curl.plan.weight == Weight(27.5, .pounds))
        curl.setWeight(1)
        #expect(curl.plan.weight == Weight(5, .pounds))
        curl.setWeight(5000)
        #expect(curl.plan.weight == Weight(1000, .pounds))
        var pushUp = try Self.row("Push-up")
        let before = pushUp.plan
        pushUp.setWeight(20)
        #expect(pushUp.plan == before)
    }

    @Test("− / + from a weight off its steps land on the next step that way")
    func weightSnaps() throws {
        var curl = try Self.row("Biceps curl") { $0.weight = Weight(27.5, .pounds) }
        curl.step(.weight, by: 1)
        #expect(curl.plan.weight == Weight(30, .pounds))
        curl.setWeight(27.5)
        curl.step(.weight, by: -1)
        #expect(curl.plan.weight == Weight(25, .pounds))
        curl.step(.weight, by: -1)
        #expect(curl.plan.weight == Weight(20, .pounds))
    }

    @Test("− / + from a time off its 5 s marks land on the next mark that way")
    func timeSnaps() throws {
        var plank = try Self.row("Plank") { $0.target = .time(seconds: 32) }
        plank.step(.target, by: 1)
        #expect(plank.plan.target == .time(seconds: 35))
        plank.plan.target = .time(seconds: 32)
        plank.step(.target, by: -1)
        #expect(plank.plan.target == .time(seconds: 30))
    }

    @Test("A time's top is the last 5 s mark a plan stores, 99m 55s, for stepper and ruler")
    func timeTop() throws {
        #expect(RoutineExercise.timeRange == 5 ... 5995)
        var plank = try Self.row("Plank") { $0.target = .time(seconds: 5990) }
        plank.step(.target, by: 1)
        #expect(plank.plan.target == .time(seconds: 5995))
        #expect(!plank.canStep(.target, by: 1))
        plank.setTime(6000)
        #expect(plank.plan.target == .time(seconds: 5995))
        plank.setTime(0)
        #expect(plank.plan.target == .time(seconds: 5))
    }

    @Test("Setting a time leaves a set of reps as it is")
    func setTimeOnReps() throws {
        var curl = try Self.row("Biceps curl")
        curl.setTime(45)
        #expect(curl.plan.target == .reps(12))
    }

    @Test("A rest set on its ruler turns Auto off; Auto on brings the automatic rest back")
    func restRulerAndAuto() throws {
        var bench = try Self.row("Barbell bench press") { $0.target = .reps(10) }
        #expect(bench.isRestAuto)
        bench.setRest(95)
        #expect(bench.rest == 95)
        #expect(!bench.isRestAuto)
        bench.isRestAuto = true
        #expect(bench.rest == 90)
        bench.isRestAuto = false
        #expect(bench.rest == 95)
        bench.setRest(900)
        #expect(bench.rest == 600)
        bench.setRest(-5)
        #expect(bench.rest == 0)
    }

    @Test("A superset's rest set on its ruler sets every member's, by hand")
    func roundRestRuler() throws {
        var routine = try Routine(exercises: [
            RoutineExercise.builtIn("Barbell bench press"),
            RoutineExercise.builtIn("Dumbbell row"),
        ])
        routine.join(routine.exercises[0].id, .below)
        let (first, second) = (routine.exercises[0].id, routine.exercises[1].id)
        routine.setRestAfterRound(95, of: first)
        #expect(routine.restAfterRound(of: second) == 95)
        #expect(!routine.isRoundAuto(of: second))
        routine.setRoundAuto(true, of: second)
        #expect(routine.isRoundAuto(of: first))
    }

    /// While its ruler shows, a value keeps one shape as it turns: a weight one decimal, a time
    /// both its units; closed, as everywhere else.
    @Test("Open and closed text, in en_US and a comma-decimal locale")
    func openAndClosedText() throws {
        let curl = try Self.row("Biceps curl") { $0.weight = Weight(25, .pounds) }
        let plank = try Self.row("Side plank") { $0.target = .time(seconds: 45) }
        let bench = try Self.row("Barbell bench press") { $0.target = .reps(10) }
        let cases: [(Locale, [String])] = [
            (Self.english, [
                "25 lb/side",
                "25.0 lb/side",
                "45s per side",
                "0m 45s per side",
                "1m 30s",
                "1m 30s",
            ]),
            (Self.german, [
                "25 lb/side",
                "25,0 lb/side",
                "45s per side",
                "0min 45s per side",
                "1min 30s",
                "1min 30s",
            ]),
        ]
        for (locale, expected) in cases {
            let texts = [
                curl.value(of: .weight, locale: locale),
                curl.dialedValue(of: .weight, locale: locale),
                plank.value(of: .target, locale: locale),
                plank.dialedValue(of: .target, locale: locale),
                bench.value(of: .rest, locale: locale),
                bench.dialedValue(of: .rest, locale: locale),
            ]
            #expect(texts.map { $0.replacingOccurrences(of: "\u{00A0}", with: " ") } == expected)
        }
        let off = try Self.row("Biceps curl") { $0.weight = Weight(27.5, .pounds) }
        #expect(off.dialedValue(of: .weight, locale: Self.german) == "27,5\u{00A0}lb/side")
    }

    @Test("Open, a time shows a zero unit too, and a minute its seconds")
    func dialedTimeZeros() {
        #expect(RoutineExercise.dialedTime(0, locale: Self.english) == "0m\u{00A0}0s")
        #expect(RoutineExercise.dialedTime(60, locale: Self.english) == "1m\u{00A0}0s")
        #expect(RoutineExercise.dialedTime(5995, locale: Self.english) == "99m\u{00A0}55s")
    }

    @Test("A rest in a sentence reads condensed, and no rest at none; spoken, in words")
    func restInSentence() {
        #expect(RoutineExercise
            .restInSentence(95, locale: Self.english) == "1\u{00A0}min\u{00A0}35\u{00A0}sec")
        #expect(RoutineExercise.restInSentence(0, locale: Self.english) == "no rest")
        #expect(RoutineExercise.restInSentence(95, spoken: true, locale: Self.english)
            == "1 minute, 35 seconds")
        #expect(RoutineExercise.restInSentence(0, spoken: true, locale: Self.english) == "no rest")
    }

    @Test("VoiceOver hears a time and a weight in full words, a pair's per side")
    func spokenValues() throws {
        let curl = try Self.row("Biceps curl") { $0.weight = Weight(27.5, .pounds) }
        #expect(curl.spokenValue(of: .weight, locale: Self.english) == "27.5 pounds per side")
        let row = try Self.row("Dumbbell row") { $0.weight = Weight(1, .kilograms) }
        #expect(row.spokenValue(of: .weight, locale: Self.english) == "1 kilogram")
        let bench = try Self.row("Barbell bench press") { $0.target = .reps(10) }
        #expect(bench.spokenValue(of: .rest, locale: Self.english) == "1 minute, 30 seconds")
    }
}

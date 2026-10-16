import Foundation
import Testing
@testable import WorkoutStore

/// How a plan reads on its row and to VoiceOver. "\u{00A0}" is the no-break space
/// between a number and its unit.
@Suite("Plan text")
struct PlanTextTests {
    private static let locale = Locale(identifier: "en_US")

    private static func row(
        _ name: String,
        sets: Int? = nil,
        target: SetTarget? = nil,
        weight: Weight? = nil,
    ) throws -> RoutineExercise {
        let exercise = try Exercise.builtIn(named: name)
        var plan = exercise.defaultPlan(in: .pounds)
        plan.sets = sets ?? plan.sets
        plan.target = target ?? plan.target
        plan.weight = weight ?? plan.weight
        return RoutineExercise(exercise: exercise, plan: plan)
    }

    private static func detail(_ row: RoutineExercise) -> String {
        row.detailParts(locale: locale).joined(separator: " · ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test("The card's four lines")
    func cardLines() throws {
        #expect(try Self.detail(Self.row("Dumbbell row", weight: Weight(50, .pounds)))
            == "3 × 10 reps per side · 50 lb")
        #expect(try Self.detail(Self.row("Biceps curl", weight: Weight(25, .pounds)))
            == "3 × 12 reps · 25 lb/side")
        #expect(try Self.detail(Self.row(
            "Barbell bench press",
            sets: 5,
            weight: Weight(135, .pounds),
        ))
            == "5 × 5 reps · 135 lb")
        #expect(try Self.detail(Self.row("Side plank")) == "3 × 30 s per side")
    }

    @Test("Numbers and units are joined by a no-break space, the sets count bare")
    func noBreakSpaces() throws {
        #expect(try Self.row("Biceps curl", weight: Weight(25, .pounds))
            .detailParts(locale: Self.locale)
            == ["3\u{00A0}×\u{00A0}12\u{00A0}reps", "25\u{00A0}lb/side"])
    }

    @Test("Kinds: one set, one rep, one weight, bodyweight, a default weight, timed with a weight")
    func kinds() throws {
        #expect(try Self.detail(Self.row("Pigeon stretch")) == "60 s per side")
        #expect(try Self.detail(Self.row("Turkish get-up"))
            == "3 × 1 rep per side · 20 lb")
        #expect(try Self.detail(Self.row("Goblet squat", weight: Weight(35, .pounds)))
            == "3 × 10 reps · 35 lb")
        #expect(try Self.detail(Self.row("Pull-up")) == "3 × 6 reps")
        #expect(try Self.detail(Self.row("Goblet squat")) == "3 × 10 reps · 35 lb")
        #expect(try Self.detail(Self.row("Farmer\u{2019}s carry", weight: Weight(50, .pounds)))
            == "3 × 30 s · 50 lb/side")
        #expect(try Self.detail(Self.row("Push-up", weight: Weight(10, .pounds))) == "3 × 10 reps")
    }

    @Test("Times read in seconds under two minutes, then minutes")
    func times() throws {
        let line = { (seconds: Int) in
            try Self.detail(Self.row("Plank", sets: 1, target: .time(seconds: seconds)))
        }
        #expect(try line(30) == "30 s")
        #expect(try line(90) == "90 s")
        #expect(try line(119) == "119 s")
        #expect(try line(120) == "2 min")
        #expect(try line(150) == "2:30 min")
        #expect(try line(605) == "10:05 min")
    }

    @Test("Weights drop trailing zeros, up to two decimals, in their own unit")
    func weights() throws {
        let line = { (weight: Weight) in
            try Self.detail(Self.row("Goblet squat", sets: 1, target: .reps(10), weight: weight))
        }
        #expect(try line(Weight(50, .pounds)) == "10 reps · 50 lb")
        #expect(try line(Weight(142.5, .pounds)) == "10 reps · 142.5 lb")
        #expect(try line(Weight(2.5, .kilograms)) == "10 reps · 2.5 kg")
        #expect(try line(Weight(1.25, .kilograms)) == "10 reps · 1.25 kg")
    }

    @Test("VoiceOver hears the plan in words")
    func spoken() throws {
        #expect(try Self.row("Dumbbell row", weight: Weight(50, .pounds))
            .spokenDetail(locale: Self.locale)
            == "3 sets of 10 reps per side, 50 pounds")
        #expect(try Self.row("Pigeon stretch").spokenDetail(locale: Self.locale)
            == "60 seconds per side")
        #expect(try Self.row("Biceps curl", weight: Weight(25, .pounds))
            .spokenDetail(locale: Self.locale) == "3 sets of 12 reps, 25 pounds per side")
        #expect(try Self.row("Plank", sets: 1, target: .time(seconds: 150))
            .spokenDetail(locale: Self.locale) == "2 minutes 30 seconds")
        #expect(try Self.row("Goblet squat").spokenDetail(locale: Self.locale)
            == "3 sets of 10 reps, 35 pounds")
        #expect(try Self.row("Barbell bench press", weight: Weight(20, .kilograms))
            .spokenDetail(locale: Self.locale) == "3 sets of 5 reps, 20 kilograms")
    }
}

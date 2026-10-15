import Foundation
import Testing
@testable import WorkoutStore

/// How a plan reads on its row, to VoiceOver, and in its sheet. "\u{00A0}" is the no-break space
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
        var plan = exercise.defaultPlan
        plan.sets = sets ?? plan.sets
        plan.target = target ?? plan.target
        plan.weight = weight
        return RoutineExercise(exercise: exercise, plan: plan)
    }

    private static func detail(_ row: RoutineExercise) -> String {
        row.detailParts(locale: locale).joined(separator: " · ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test("The card's four lines")
    func cardLines() throws {
        #expect(try Self.detail(Self.row("Dumbbell row", weight: Weight(50, .pounds)))
            == "Dumbbells, bench · 3 × 10 reps per side · 50 lb")
        #expect(try Self.detail(Self.row("Biceps curl", weight: Weight(25, .pounds)))
            == "Dumbbells · 3 × 12 reps · 25 lb each")
        #expect(try Self.detail(Self.row(
            "Barbell bench press",
            sets: 5,
            weight: Weight(135, .pounds),
        ))
            == "Barbell, bench · 5 × 5 reps · 135 lb")
        #expect(try Self.detail(Self.row("Side plank")) == "3 × 30 s per side")
    }

    @Test("Numbers and units are joined by a no-break space, the sets count bare")
    func noBreakSpaces() throws {
        #expect(try Self.row("Biceps curl", weight: Weight(25, .pounds))
            .detailParts(locale: Self.locale)
            == ["Dumbbells", "3\u{00A0}×\u{00A0}12\u{00A0}reps", "25\u{00A0}lb each"])
    }

    @Test("Kinds: one set, one rep, one weight, bodyweight, unset, timed with a weight")
    func kinds() throws {
        #expect(try Self.detail(Self.row("Pigeon stretch")) == "60 s per side")
        #expect(try Self.detail(Self.row("Turkish get-up")) == "Kettlebell · 3 × 1 rep per side")
        #expect(try Self.detail(Self.row("Goblet squat", weight: Weight(35, .pounds)))
            == "Kettlebell · 3 × 10 reps · 35 lb")
        #expect(try Self.detail(Self.row("Pull-up")) == "Pull-up bar · 3 × 6 reps")
        #expect(try Self.detail(Self.row("Goblet squat")) == "Kettlebell · 3 × 10 reps")
        #expect(try Self.detail(Self.row("Farmer\u{2019}s carry", weight: Weight(50, .pounds)))
            == "Dumbbells · 3 × 30 s · 50 lb each")
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
        #expect(try line(Weight(50, .pounds)) == "Kettlebell · 10 reps · 50 lb")
        #expect(try line(Weight(142.5, .pounds)) == "Kettlebell · 10 reps · 142.5 lb")
        #expect(try line(Weight(2.5, .kilograms)) == "Kettlebell · 10 reps · 2.5 kg")
        #expect(try line(Weight(1.25, .kilograms)) == "Kettlebell · 10 reps · 1.25 kg")
    }

    @Test("VoiceOver hears the plan in words")
    func spoken() throws {
        #expect(try Self.row("Dumbbell row", weight: Weight(50, .pounds))
            .spokenDetail(locale: Self.locale)
            == "Dumbbells, bench, 3 sets of 10 reps per side, 50 pounds")
        #expect(try Self.row("Pigeon stretch").spokenDetail(locale: Self.locale)
            == "60 seconds per side")
        #expect(try Self.row("Biceps curl", weight: Weight(25, .pounds))
            .spokenDetail(locale: Self.locale) == "Dumbbells, 3 sets of 12 reps, 25 pounds each")
        #expect(try Self.row("Plank", sets: 1, target: .time(seconds: 150))
            .spokenDetail(locale: Self.locale) == "2 minutes 30 seconds")
        #expect(try Self.row("Goblet squat").spokenDetail(locale: Self.locale)
            == "Kettlebell, 3 sets of 10 reps")
        #expect(try Self.row("Barbell bench press", weight: Weight(20, .kilograms))
            .spokenDetail(locale: Self.locale) == "Barbell, bench, 3 sets of 5 reps, 20 kilograms")
    }

    @Test("The sheet's labels, notes, and values")
    func sheet() throws {
        let row = try Self.row("Dumbbell row")
        #expect([PlanPart.sets, .target, .weight].map(row.label(of:)) == ["Sets", "Reps", "Weight"])
        #expect(row.note(of: .target) == "Per side")
        #expect(row.note(of: .weight) == "One dumbbell")
        #expect(try Self.row("Goblet squat").note(of: .weight) == "One kettlebell")
        #expect(try Self.row("Biceps curl").note(of: .weight) == "Pair, each")
        #expect(try Self.row("Barbell bench press").note(of: .weight) == "Bar, total")
        #expect(try Self.row("Barbell bench press").note(of: .target) == nil)
        let pigeon = try Self.row("Pigeon stretch")
        #expect(pigeon.label(of: .target) == "Time")
        #expect(pigeon.value(of: .target, locale: Self.locale) == PlanValue("60", unit: "s"))
        #expect(row.value(of: .weight, locale: Self.locale) == nil)
        #expect(row.spokenValue(of: .weight, locale: Self.locale) == "Not set")
        let bench = try Self.row("Barbell bench press", weight: Weight(135, .pounds))
        #expect(bench.value(of: .weight, locale: Self.locale) == PlanValue("135", unit: "lb"))
        let long = try Self.row("Plank", target: .time(seconds: 150))
        #expect(long.value(of: .target, locale: Self.locale) == PlanValue("2:30", unit: "min"))
    }
}

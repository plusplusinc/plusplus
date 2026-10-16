import Foundation
import Testing
@testable import WorkoutStore

/// A row's values one part at a time, as its sheet shows, speaks, and steps them.
@Suite("Plan values")
struct PlanValueTests {
    private static let locale = Locale(identifier: "en_US")

    private static func row(_ name: String, edit: (inout ExercisePlan) -> Void = { _ in })
        throws -> RoutineExercise
    {
        try RoutineExercise.builtIn(name, edit)
    }

    private static func values(_ row: RoutineExercise) -> [String] {
        row.exercise.planParts.map {
            "\(row.label(of: $0)) \(row.value(of: $0, locale: locale))"
                .replacingOccurrences(of: "\u{00A0}", with: " ")
        }
    }

    @Test("Each part reads under its label, saying when it's per side")
    func shown() throws {
        #expect(try Self.values(Self.row("Bulgarian split squat"))
            == ["Sets 3", "Reps 10 per side", "Weight 20 lb/side"])
        #expect(try Self.values(Self.row("Barbell bench press"))
            == ["Sets 3", "Reps 5", "Weight 45 lb"])
        #expect(try Self.values(Self.row("Pigeon stretch") { $0.target = .time(seconds: 150) })
            == ["Sets 1", "Time 2:30 min per side"])
        #expect(try Self.values(Self.row("Push-up")) == ["Sets 3", "Reps 10"])
    }

    @Test("VoiceOver hears each part's value in words")
    func spoken() throws {
        let split = try Self.row("Bulgarian split squat")
        #expect(split.exercise.planParts.map { split.spokenValue(of: $0, locale: Self.locale) }
            == ["3 sets", "10 reps per side", "20 pounds per side"])
        let stretch = try Self.row("Pigeon stretch")
        #expect(stretch.spokenValue(of: .sets, locale: Self.locale) == "1 set")
        #expect(stretch.spokenValue(of: .target, locale: Self.locale) == "60 seconds per side")
    }

    @Test("A step moves a set or a rep by one, a time by 5 s, a weight by its unit's step")
    func steps() throws {
        var row = try Self.row("Biceps curl")
        row.step(.sets, by: 1)
        row.step(.target, by: -1)
        row.step(.weight, by: 1)
        #expect(row.plan == ExercisePlan(sets: 4, target: .reps(11), weight: Weight(20, .pounds)))
        var kilograms = try RoutineExercise(
            exercise: Exercise.builtIn(named: "Goblet squat"),
            weightUnit: .kilograms,
        )
        kilograms.step(.weight, by: 1)
        #expect(kilograms.plan.weight == Weight(18.5, .kilograms))
        var plank = try Self.row("Plank")
        plank.step(.target, by: 1)
        #expect(plank.plan.target == .time(seconds: 35))
    }

    @Test("Steps stop at the stored limits, a time at 5 s, a weight at a step, a bar empty")
    func limits() throws {
        var low = try Self.row("Goblet squat") {
            $0.sets = 1
            $0.target = .reps(1)
            $0.weight = Weight(5, .pounds)
        }
        low.step(.sets, by: -1)
        low.step(.target, by: -1)
        low.step(.weight, by: -1)
        #expect(low.plan == ExercisePlan(sets: 1, target: .reps(1), weight: Weight(5, .pounds)))

        var high = try Self.row("Goblet squat") {
            $0.sets = 99
            $0.target = .reps(999)
        }
        high.step(.sets, by: 1)
        high.step(.target, by: 1)
        #expect(high.plan.sets == 99)
        #expect(high.plan.target == .reps(999))

        var plank = try Self.row("Plank") { $0.target = .time(seconds: 5) }
        plank.step(.target, by: -1)
        #expect(plank.plan.target == .time(seconds: 5))
        plank.plan.target = .time(seconds: 5999)
        plank.step(.target, by: 1)
        #expect(plank.plan.target == .time(seconds: 5999))

        var bar = try Self.row("Barbell row")
        bar.step(.weight, by: -1)
        #expect(bar.plan.weight == Weight(45, .pounds))
    }
}

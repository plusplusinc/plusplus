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

    @Test("A step moves a set or a rep by one, a time by 5 s, a weight by its load's step")
    func steps() throws {
        var row = try Self.row("Biceps curl")
        row.step(.sets, by: 1)
        row.step(.target, by: -1)
        row.step(.weight, by: 1)
        #expect(row.plan == ExercisePlan(sets: 4, target: .reps(11), weight: Weight(20, .pounds)))
        var plank = try Self.row("Plank")
        plank.step(.target, by: 1)
        #expect(plank.plan.target == .time(seconds: 35))
    }

    @Test("In kilograms a hand-held weight steps 2 kg, as its kit comes, and a bar 2.5 kg")
    func kilogramSteps() throws {
        func stepped(_ name: String) throws -> Weight? {
            var row = try RoutineExercise(
                exercise: Exercise.builtIn(named: name),
                weightUnit: .kilograms,
            )
            row.step(.weight, by: 1)
            return row.plan.weight
        }
        #expect(try stepped("Overhead press") == Weight(8, .kilograms))
        #expect(try stepped("Goblet squat") == Weight(18, .kilograms))
        #expect(try stepped("Barbell row") == Weight(22.5, .kilograms))
    }

    @Test("Steps stop at the stored limits, a time at 5 s, a weight at a step, a bar empty")
    func limits() throws {
        var low = try Self.row("Goblet squat") {
            $0.sets = 1
            $0.target = .reps(1)
            $0.weight = Weight(5, .pounds)
        }
        for part in low.exercise.planParts {
            #expect(!low.canStep(part, by: -1))
            #expect(low.canStep(part, by: 1))
            low.step(part, by: -1)
        }
        #expect(low.plan == ExercisePlan(sets: 1, target: .reps(1), weight: Weight(5, .pounds)))

        var high = try Self.row("Goblet squat") {
            $0.sets = 99
            $0.target = .reps(999)
            $0.weight = Weight(995, .pounds)
        }
        for part in high.exercise.planParts {
            high.step(part, by: 1)
            #expect(!high.canStep(part, by: 1))
            high.step(part, by: 1)
        }
        #expect(high.plan == ExercisePlan(sets: 99, target: .reps(999), weight: Weight(1000, .pounds)))
        #expect(high.canStep(.weight, by: -1))

        var plank = try Self.row("Plank") { $0.target = .time(seconds: 5) }
        #expect(!plank.canStep(.target, by: -1))
        plank.step(.target, by: -1)
        #expect(plank.plan.target == .time(seconds: 5))
        plank.plan.target = .time(seconds: 5999)
        #expect(!plank.canStep(.target, by: 1))
        plank.step(.target, by: 1)
        #expect(plank.plan.target == .time(seconds: 5999))

        var bar = try Self.row("Barbell row")
        #expect(!bar.canStep(.weight, by: -1))
        bar.step(.weight, by: -1)
        #expect(bar.plan.weight == Weight(45, .pounds))
    }

    @Test("A stepper's ends are values a plan can be stored with")
    func limitsAreStorable() throws {
        var plank = try Self.row("Plank") { $0.target = .time(seconds: 10) }
        plank.step(.target, by: -1)
        plank.step(.target, by: -1)
        #expect(plank.plan.target == .time(seconds: 5))
        #expect(PlanLimits.seconds.contains(5))
        for unit in [WeightUnit.pounds, .kilograms] {
            for name in ["Overhead press", "Goblet squat", "Barbell row"] {
                var row = try RoutineExercise(exercise: Exercise.builtIn(named: name), weightUnit: unit)
                while row.canStep(.weight, by: -1) {
                    row.step(.weight, by: -1)
                }
                let weight = try #require(row.plan.weight)
                #expect(PlanLimits.weight.contains(weight.amount), "\(name) in \(unit)")
            }
        }
    }
}

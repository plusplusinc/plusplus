import Foundation
import Testing
@testable import WorkoutStore

/// The sheet's − and + keys.
@Suite("Plan steps")
struct PlanStepTests {
    private static func stepped(
        _ row: RoutineExercise,
        _ part: PlanPart,
        up: Bool,
        unit: WeightUnit = .pounds,
    ) -> ExercisePlan {
        var row = row
        row.step(part, up: up, newWeightUnit: unit)
        return row.plan
    }

    @Test("Sets and reps step by one and stop at 1 and 99 or 999")
    func setsAndReps() throws {
        let row = try RoutineExercise.builtIn("Push-up")
        #expect(Self.stepped(row, .sets, up: true).sets == 4)
        #expect(Self.stepped(row, .target, up: false).target == .reps(9))
        let low = try RoutineExercise.builtIn("Push-up") {
            $0.sets = 1
            $0.target = .reps(1)
        }
        #expect(!low.canStep(.sets, up: false))
        #expect(!low.canStep(.target, up: false))
        let high = try RoutineExercise.builtIn("Push-up") {
            $0.sets = 99
            $0.target = .reps(999)
        }
        #expect(!high.canStep(.sets, up: true))
        #expect(!high.canStep(.target, up: true))
        #expect(Self.stepped(high, .sets, up: true).sets == 99)
    }

    @Test("Time steps by 5 s under a minute and 15 s from one, stopping at 5 s and 99:59")
    func time() throws {
        let at = { (seconds: Int) in
            try RoutineExercise.builtIn("Plank") { $0.target = .time(seconds: seconds) }
        }
        let up = { (seconds: Int) in try Self.stepped(at(seconds), .target, up: true).target }
        let down = { (seconds: Int) in try Self.stepped(at(seconds), .target, up: false).target }
        #expect(try up(55) == .time(seconds: 60))
        #expect(try up(60) == .time(seconds: 75))
        #expect(try up(57) == .time(seconds: 60))
        #expect(try down(75) == .time(seconds: 60))
        #expect(try down(60) == .time(seconds: 55))
        #expect(try down(65) == .time(seconds: 60))
        #expect(try down(7) == .time(seconds: 5))
        #expect(try !at(5).canStep(.target, up: false))
        #expect(try !at(3).canStep(.target, up: false))
        #expect(try up(5990) == .time(seconds: 5999))
        #expect(try !at(5999).canStep(.target, up: true))
    }

    @Test("A weight steps by 5 lb or 2.5 kg, snapping to the grid, in its own unit")
    func weight() throws {
        let at = { (weight: Weight) in
            try RoutineExercise.builtIn("Goblet squat") { $0.weight = weight }
        }
        #expect(try Self.stepped(at(Weight(142.5, .pounds)), .weight, up: true).weight
            == Weight(145, .pounds))
        #expect(try Self.stepped(at(Weight(142.5, .pounds)), .weight, up: false).weight
            == Weight(140, .pounds))
        #expect(try Self.stepped(at(Weight(20, .kilograms)), .weight, up: true, unit: .pounds)
            .weight == Weight(22.5, .kilograms))
        #expect(try Self.stepped(at(Weight(5, .pounds)), .weight, up: false).weight == nil)
        #expect(try Self.stepped(at(Weight(3, .pounds)), .weight, up: false).weight == nil)
        #expect(try Self.stepped(at(Weight(9998, .pounds)), .weight, up: true).weight
            == Weight(9999, .pounds))
    }

    @Test("From not set, + gives the empty bar for a bar and one step for anything else")
    func fromNotSet() throws {
        let row = try RoutineExercise.builtIn("Dumbbell row")
        #expect(!row.canStep(.weight, up: false))
        #expect(row.canStep(.weight, up: true))
        #expect(Self.stepped(row, .weight, up: true).weight == Weight(5, .pounds))
        #expect(Self.stepped(row, .weight, up: true, unit: .kilograms).weight
            == Weight(2.5, .kilograms))
        let bench = try RoutineExercise.builtIn("Barbell bench press")
        #expect(Self.stepped(bench, .weight, up: true).weight == Weight(45, .pounds))
        #expect(Self.stepped(bench, .weight, up: true, unit: .kilograms).weight
            == Weight(20, .kilograms))
        #expect(try !RoutineExercise.builtIn("Push-up").canStep(.weight, up: true))
    }

    @Test("A key's label is the step it takes: +1, −5 s or +15 s, +45 for a bar not set")
    func labels() throws {
        let us = Locale(identifier: "en_US")
        let label = { (row: RoutineExercise, part: PlanPart, up: Bool, unit: WeightUnit) in
            row.stepLabel(of: part, up: up, newWeightUnit: unit, locale: us)
        }
        let bench = try RoutineExercise.builtIn("Barbell bench press")
        #expect(label(bench, .sets, false, .pounds) == "\u{2212}1")
        #expect(label(bench, .target, true, .pounds) == "+1")
        #expect(label(bench, .weight, true, .pounds) == "+45")
        #expect(label(bench, .weight, true, .kilograms) == "+20")
        #expect(label(bench, .weight, false, .pounds) == "\u{2212}5")
        let row = try RoutineExercise.builtIn("Dumbbell row") { $0.weight = Weight(20, .kilograms) }
        #expect(label(row, .weight, true, .pounds) == "+2.5")
        let plank = { (seconds: Int) in
            try RoutineExercise.builtIn("Plank") { $0.target = .time(seconds: seconds) }
        }
        #expect(try label(plank(55), .target, true, .pounds) == "+5\u{00A0}s")
        #expect(try label(plank(60), .target, true, .pounds) == "+15\u{00A0}s")
        #expect(try label(plank(60), .target, false, .pounds) == "\u{2212}5\u{00A0}s")
        #expect(try label(plank(75), .target, false, .pounds) == "\u{2212}15\u{00A0}s")
    }

    @Test("A new weight takes the region's unit: lb in the US, kg elsewhere")
    func regionUnit() {
        #expect(WeightUnit(region: Locale(identifier: "en_US")) == .pounds)
        #expect(WeightUnit(region: Locale(identifier: "en_GB")) == .kilograms)
        #expect(WeightUnit(region: Locale(identifier: "de_DE")) == .kilograms)
    }
}

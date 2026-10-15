import Foundation
import Testing
@testable import WorkoutStore

/// The sheet's wheels: what each part offers, and what picking sets.
@Suite("Plan choices")
struct PlanChoiceTests {
    @Test("Sets offer 1 to 20 and reps 1 to 100, each with a saved value outside them in place")
    func setsAndReps() throws {
        let row = try RoutineExercise.builtIn("Push-up")
        #expect(row.setChoices == Array(1 ... 20))
        #expect(row.repChoices == Array(1 ... 100))
        let wide = try RoutineExercise.builtIn("Push-up") {
            $0.sets = 30
            $0.target = .reps(150)
        }
        #expect(wide.setChoices.last == 30)
        #expect(wide.repChoices.last == 150)
        #expect(try RoutineExercise.builtIn("Plank").repChoices.isEmpty)
    }

    @Test("A time offers minutes 0 to 60 and seconds in 5 s steps, a saved odd second in place")
    func time() throws {
        let plank = { (seconds: Int) in
            try RoutineExercise.builtIn("Plank") { $0.target = .time(seconds: seconds) }
        }
        #expect(try plank(90).minutesAndSeconds == (1, 30))
        #expect(try plank(90).minuteChoices == Array(0 ... 60))
        #expect(try plank(90).secondChoices == Array(stride(from: 0, through: 55, by: 5)))
        #expect(try plank(58).secondChoices.contains(58))
        var row = try plank(90)
        row.setTime(minutes: 2, seconds: 15)
        #expect(row.plan.target == .time(seconds: 135))
        row.setTime(minutes: 0, seconds: 0)
        #expect(row.plan.target == .time(seconds: 5))
    }

    @Test("A weight's wheel runs its unit's steps from the lightest to the heaviest")
    func weights() throws {
        let bench = try RoutineExercise.builtIn("Barbell bench press")
        #expect(bench.weightChoices.first == 45)
        #expect(bench.weightChoices.last == 500)
        #expect(bench.weightChoices.dropFirst().first == 50)
        let curl = try RoutineExercise.builtIn("Biceps curl") { $0.weight = Weight(10, .kilograms) }
        #expect(curl.weightChoices.first == 2.5)
        #expect(curl.weightChoices.last == 70)
        #expect(try RoutineExercise.builtIn("Push-up").weightChoices.isEmpty)
    }

    @Test("A saved weight off the grid or under the floor is on the wheel, in its place")
    func savedWeightInPlace() throws {
        let row = try RoutineExercise.builtIn("Dumbbell row") { $0.weight = Weight(42.5, .pounds) }
        #expect(row.weightChoices.contains(42.5))
        #expect(row.weightChoices.firstIndex(of: 42.5) == row.weightChoices.firstIndex(of: 40)
            .map { $0 + 1 })
        let bench = try RoutineExercise.builtIn("Barbell bench press") {
            $0.weight = Weight(35, .pounds)
        }
        #expect(bench.weightChoices.first == 35)
        #expect(bench.weightChoices.dropFirst().first == 45)
    }

    @Test("Picking a weight keeps its unit")
    func pickKeepsUnit() throws {
        var row = try RoutineExercise.builtIn("Goblet squat") { $0.weight = Weight(16, .kilograms) }
        row.setWeight(20)
        #expect(row.plan.weight == Weight(20, .kilograms))
    }

    @Test("A new weight takes the region's unit: lb in the US, kg elsewhere")
    func regionUnit() {
        #expect(WeightUnit(region: Locale(identifier: "en_US")) == .pounds)
        #expect(WeightUnit(region: Locale(identifier: "en_GB")) == .kilograms)
        #expect(WeightUnit(region: Locale(identifier: "de_DE")) == .kilograms)
    }
}

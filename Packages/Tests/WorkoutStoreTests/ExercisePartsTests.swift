import Foundation
import Testing
@testable import WorkoutStore

/// Each built-in's parts, set by hand: how a set is measured with its default, what it holds,
/// and whether it is per side.
@Suite("Exercise parts")
struct ExercisePartsTests {
    private struct Parts: Equatable, CustomStringConvertible {
        let name: String
        let sets: Int
        let target: SetTarget
        var load: Load?
        var perSide = false

        init(_ name: String, _ sets: Int, _ target: SetTarget, _ load: Load?, _ perSide: Bool) {
            self.name = name
            self.sets = sets
            self.target = target
            self.load = load
            self.perSide = perSide
        }

        var description: String {
            name
        }
    }

    private static let table: [Parts] = [
        Parts("Balance board hold", 3, .time(seconds: 30), nil, false),
        Parts("Band pull-apart", 3, .reps(15), nil, false),
        Parts("Band shoulder dislocate", 1, .reps(10), nil, false),
        Parts("Barbell back squat", 3, .reps(5), .bar, false),
        Parts("Barbell bench press", 3, .reps(5), .bar, false),
        Parts("Barbell deadlift", 3, .reps(5), .bar, false),
        Parts("Barbell overhead press", 3, .reps(5), .bar, false),
        Parts("Barbell row", 3, .reps(8), .bar, false),
        Parts("Biceps curl", 3, .reps(12), .pair, false),
        Parts("Bulgarian split squat", 3, .reps(10), .pair, true),
        Parts("Calf raise", 3, .reps(15), .pair, false),
        Parts("Calf stretch", 1, .time(seconds: 30), nil, true),
        Parts("Cat-cow", 1, .reps(10), nil, false),
        Parts("Child\u{2019}s pose", 1, .time(seconds: 60), nil, false),
        Parts("Chin-up", 3, .reps(6), nil, false),
        Parts("Cross-body shoulder stretch", 1, .time(seconds: 30), nil, true),
        Parts("Dead bug", 3, .reps(10), nil, false),
        Parts("Dead hang", 3, .time(seconds: 30), nil, false),
        Parts("Doorway chest stretch", 1, .time(seconds: 60), nil, false),
        Parts("Dumbbell bench press", 3, .reps(10), .pair, false),
        Parts("Dumbbell row", 3, .reps(10), .single, true),
        Parts("Face pull", 3, .reps(15), nil, false),
        Parts("Farmer\u{2019}s carry", 3, .time(seconds: 30), .pair, false),
        Parts("Glute bridge", 3, .reps(12), nil, false),
        Parts("Goblet squat", 3, .reps(10), .single, false),
        Parts("Hammer curl", 3, .reps(12), .pair, false),
        Parts("Hamstring stretch", 1, .time(seconds: 60), nil, true),
        Parts("Hanging knee raise", 3, .reps(10), nil, false),
        Parts("Incline dumbbell press", 3, .reps(10), .pair, false),
        Parts("Inverted row", 3, .reps(10), nil, false),
        Parts("Kettlebell swing", 3, .reps(15), .single, false),
        Parts("Kneeling hip flexor stretch", 1, .time(seconds: 60), nil, true),
        Parts("Lateral raise", 3, .reps(12), .pair, false),
        Parts("Overhead press", 3, .reps(10), .pair, false),
        Parts("Pallof press", 3, .reps(10), nil, true),
        Parts("Pigeon stretch", 1, .time(seconds: 60), nil, true),
        Parts("Plank", 3, .time(seconds: 30), nil, false),
        Parts("Pull-up", 3, .reps(6), nil, false),
        Parts("Push-up", 3, .reps(10), nil, false),
        Parts("Reverse lunge", 3, .reps(10), .pair, true),
        Parts("Ring dip", 3, .reps(8), nil, false),
        Parts("Ring push-up", 3, .reps(10), nil, false),
        Parts("Romanian deadlift", 3, .reps(10), .pair, false),
        Parts("Side plank", 3, .time(seconds: 30), nil, true),
        Parts("Step-up", 3, .reps(10), .pair, true),
        Parts("Thoracic rotation", 1, .reps(10), nil, true),
        Parts("Triceps extension", 3, .reps(12), .single, false),
        Parts("Turkish get-up", 3, .reps(1), .single, true),
        Parts("World\u{2019}s greatest stretch", 1, .reps(5), nil, true),
    ]

    @Test("Every built-in has the defaults table's parts")
    func table() {
        let actual = Exercise.builtIn.map {
            Parts(
                $0.name,
                $0.defaultPlan(in: .pounds).sets,
                $0.defaultPlan(in: .pounds).target,
                $0.load,
                $0.isPerSide,
            )
        }
        #expect(actual.count == Self.table.count)
        for (actual, expected) in zip(actual, Self.table) {
            #expect(actual == expected)
        }
    }

    @Test("The totals: 37 reps, 12 time; 5 one weight, 12 pairs, 5 bars; 14 per side")
    func totals() {
        let all = Exercise.builtIn
        #expect(all.count {
            if case .reps = $0.defaultPlan(in: .pounds).target {
                true
            } else {
                false
            }
        } == 37)
        #expect(all.count {
            if case .time = $0.defaultPlan(in: .pounds).target {
                true
            } else {
                false
            }
        } == 12)
        #expect(all.count { $0.load == .single } == 5)
        #expect(all.count { $0.load == .pair } == 12)
        #expect(all.count { $0.load == .bar } == 5)
        #expect(all.count { $0.load == nil } == 27)
        #expect(all.count(where: \.isPerSide) == 14)
    }

    @Test("A load goes with the kit that holds it, and starts at a weight that kit comes in")
    func loadsMatchEquipment() {
        for exercise in Exercise.builtIn {
            let (pounds, kilograms) = (
                exercise.defaultPlan(in: .pounds).weight,
                exercise.defaultPlan(in: .kilograms).weight,
            )
            #expect((pounds == nil) == (exercise.load == nil), "\(exercise.name)")
            #expect(
                (exercise.startsAt == nil) == (exercise.load != .single && exercise.load != .pair),
                "\(exercise.name)",
            )
            if exercise.load == .bar {
                #expect(pounds == Weight(45, .pounds), "\(exercise.name)")
                #expect(kilograms == Weight(20, .kilograms), "\(exercise.name)")
            }
            if let pounds, let kilograms, exercise.load != .bar {
                #expect(pounds.amount.truncatingRemainder(dividingBy: 5) == 0, "\(exercise.name)")
                // Dumbbells come in 2 kg steps, kettlebells in 4.
                let kilogramStep: Double = exercise.equipment.contains(.kettlebell) ? 4 : 2
                #expect(
                    kilograms.amount.truncatingRemainder(dividingBy: kilogramStep) == 0,
                    "\(exercise.name)",
                )
            }
            let hasBarbell = exercise.equipment.contains(.barbell)
            #expect((exercise.load == .bar) == hasBarbell, "\(exercise.name)")
            if exercise.load == .single || exercise.load == .pair {
                #expect(
                    !exercise.equipment.isDisjoint(with: [.dumbbells, .kettlebell]),
                    "\(exercise.name)",
                )
            }
            if exercise.equipment.isDisjoint(with: [.dumbbells, .kettlebell, .barbell]) {
                #expect(exercise.load == nil, "\(exercise.name)")
            }
        }
    }

    @Test("A new row starts with its exercise's default plan, and has only its exercise's parts")
    func newRowAndParts() throws {
        let bench = try Exercise.builtIn(named: "Barbell bench press")
        #expect(RoutineExercise(exercise: bench, weightUnit: .pounds).plan == bench
            .defaultPlan(in: .pounds))
        #expect(bench.planParts == [.sets, .target, .weight])
        #expect(try Exercise.builtIn(named: "Pigeon stretch").planParts == [.sets, .target])
    }

    @Test("A new weight takes the region's unit: lb in the US, kg elsewhere")
    func regionUnit() {
        #expect(WeightUnit(region: Locale(identifier: "en_US")) == .pounds)
        #expect(WeightUnit(region: Locale(identifier: "en_GB")) == .kilograms)
        #expect(WeightUnit(region: Locale(identifier: "de_DE")) == .kilograms)
    }
}

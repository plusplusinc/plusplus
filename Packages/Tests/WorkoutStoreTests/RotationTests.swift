import Foundation
import Testing
@testable import WorkoutStore

@Suite("Rotation")
struct RotationTests {
    private func order(_ workout: Workout, _ names: [WorkoutExercise.ID: String]) -> [String] {
        workout.setOrder.map { set in
            let side = switch set.side {
            case .left: "L"
            case .right: "R"
            case nil: ""
            }
            return "\(names[set.row] ?? "?")\(set.round)\(side)"
        }
    }

    @Test("A superset of two with three rounds goes A1 B1 A2 B2 A3 B3")
    func superset() throws {
        let superset = UUID()
        var first = try WorkoutExercise.builtIn("Push-up") { $0.sets = 3 }
        var second = try WorkoutExercise.builtIn("Pull-up") { $0.sets = 3 }
        first.supersetID = superset
        second.supersetID = superset
        let workout = Workout(exercises: [first, second])
        #expect(order(workout, [first.id: "A", second.id: "B"])
            == ["A1", "B1", "A2", "B2", "A3", "B3"])
    }

    @Test("A plain row's sets go in a row, and groups go in the routine's order")
    func mixed() throws {
        let superset = UUID()
        let plain = try WorkoutExercise.builtIn("Plank") { $0.sets = 3 }
        var first = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
        var second = try WorkoutExercise.builtIn("Pull-up") { $0.sets = 2 }
        let last = try WorkoutExercise.builtIn("Goblet squat") { $0.sets = 1 }
        first.supersetID = superset
        second.supersetID = superset
        let workout = Workout(exercises: [plain, first, second, last])
        let names = [plain.id: "C", first.id: "A", second.id: "B", last.id: "D"]
        #expect(order(workout, names) == ["C1", "C2", "C3", "A1", "B1", "A2", "B2", "D1"])
    }

    @Test("A member with fewer sets drops out of the later rounds")
    func unequal() throws {
        let superset = UUID()
        var first = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        var second = try WorkoutExercise.builtIn("Pull-up") { $0.sets = 3 }
        first.supersetID = superset
        second.supersetID = superset
        let workout = Workout(exercises: [first, second])
        #expect(order(workout, [first.id: "A", second.id: "B"]) == ["A1", "B1", "B2", "B3"])
    }

    @Test("A per-side exercise goes left then right in each set")
    func perSide() throws {
        let row = try WorkoutExercise.builtIn("Dumbbell row") { $0.sets = 2 }
        let workout = Workout(exercises: [row])
        #expect(order(workout, [row.id: "A"]) == ["A1L", "A1R", "A2L", "A2R"])
    }

    @Test("A per-side member keeps its sides together in a superset round")
    func perSideInSuperset() throws {
        let superset = UUID()
        var first = try WorkoutExercise.builtIn("Dumbbell row") { $0.sets = 2 }
        var second = try WorkoutExercise.builtIn("Pull-up") { $0.sets = 2 }
        first.supersetID = superset
        second.supersetID = superset
        let workout = Workout(exercises: [first, second])
        #expect(order(workout, [first.id: "A", second.id: "B"])
            == ["A1L", "A1R", "B1", "A2L", "A2R", "B2"])
    }
}

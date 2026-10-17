import Foundation
import Testing
@testable import WorkoutStore

@Suite("Rotation")
struct RotationTests {
    private func order(_ routine: Routine, _ names: [RoutineExercise.ID: String]) -> [String] {
        routine.setOrder.map { "\(names[$0.row] ?? "?")\($0.round)" }
    }

    @Test("A superset of two with three rounds goes A1 B1 A2 B2 A3 B3")
    func superset() throws {
        let superset = UUID()
        var first = try RoutineExercise.builtIn("Push-up") { $0.sets = 3 }
        var second = try RoutineExercise.builtIn("Pull-up") { $0.sets = 3 }
        first.supersetID = superset
        second.supersetID = superset
        let routine = Routine(exercises: [first, second])
        #expect(order(routine, [first.id: "A", second.id: "B"])
            == ["A1", "B1", "A2", "B2", "A3", "B3"])
    }

    @Test("A plain row's sets go in a row, and groups go in the routine's order")
    func mixed() throws {
        let superset = UUID()
        let plain = try RoutineExercise.builtIn("Plank") { $0.sets = 3 }
        var first = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        var second = try RoutineExercise.builtIn("Pull-up") { $0.sets = 2 }
        let last = try RoutineExercise.builtIn("Goblet squat") { $0.sets = 1 }
        first.supersetID = superset
        second.supersetID = superset
        let routine = Routine(exercises: [plain, first, second, last])
        let names = [plain.id: "C", first.id: "A", second.id: "B", last.id: "D"]
        #expect(order(routine, names) == ["C1", "C2", "C3", "A1", "B1", "A2", "B2", "D1"])
    }

    @Test("A member with fewer sets drops out of the later rounds")
    func unequal() throws {
        let superset = UUID()
        var first = try RoutineExercise.builtIn("Push-up") { $0.sets = 1 }
        var second = try RoutineExercise.builtIn("Pull-up") { $0.sets = 3 }
        first.supersetID = superset
        second.supersetID = superset
        let routine = Routine(exercises: [first, second])
        #expect(order(routine, [first.id: "A", second.id: "B"]) == ["A1", "B1", "B2", "B3"])
    }
}

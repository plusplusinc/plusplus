import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Superset mutations")
struct SupersetTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("superset-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeExercise(_ name: String, in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: .shoulders)
        context.insert(exercise)
        return exercise
    }

    @Test("Adding in a new group appends at the end")
    func addInNewGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let first = routine.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        let second = routine.addExerciseInNewGroup(makeExercise("T Raise", in: context), context: context)

        #expect(routine.sortedGroups.count == 2)
        #expect(routine.sortedGroups[0] === first)
        #expect(routine.sortedGroups[1] === second)
        #expect(routine.sortedGroups.map(\.order) == [0, 1])
        #expect(!first.isSuperset)
    }

    @Test("Adding to an existing group forms a superset in order")
    func addToGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let group = routine.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        routine.addExercise(makeExercise("T Raise", in: context), to: group, context: context)

        #expect(group.isSuperset)
        #expect(group.sortedExercises.count == 2)
        #expect(group.sortedExercises.map(\.order) == [0, 1])
        #expect(group.sortedExercises.map { $0.exercise?.name } == ["Y Raise", "T Raise"])
        #expect(routine.sortedGroups.count == 1)
    }

    @Test("Splitting moves the exercise into its own group right after")
    func splitExercise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let superset = routine.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        superset.sets = 4
        routine.addExercise(makeExercise("T Raise", in: context), to: superset, context: context)
        let trailing = routine.addExerciseInNewGroup(makeExercise("Band Pulses", in: context), context: context)

        let tRaise = superset.sortedExercises[1]
        routine.splitExercise(tRaise, context: context)

        let groups = routine.sortedGroups
        #expect(groups.count == 3)
        #expect(groups.map(\.order) == [0, 1, 2])
        #expect(groups[0] === superset)
        #expect(groups[1].sortedExercises.map { $0.exercise?.name } == ["T Raise"])
        #expect(groups[1].sets == 4, "Split group inherits the source group's set count")
        #expect(groups[2] === trailing)
        #expect(!superset.isSuperset)
        #expect(superset.sortedExercises.map(\.order) == [0])
    }

    @Test("Splitting a solo exercise is a no-op")
    func splitSoloIsNoOp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let group = routine.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        let solo = group.sortedExercises[0]
        routine.splitExercise(solo, context: context)

        #expect(routine.sortedGroups.count == 1)
        #expect(solo.group === group)
    }

    @Test("Three-exercise superset splits cleanly from the middle")
    func splitFromMiddle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let superset = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExercise(makeExercise("B", in: context), to: superset, context: context)
        routine.addExercise(makeExercise("C", in: context), to: superset, context: context)

        let middle = superset.sortedExercises[1]
        routine.splitExercise(middle, context: context)

        #expect(superset.sortedExercises.map { $0.exercise?.name } == ["A", "C"])
        #expect(superset.sortedExercises.map(\.order) == [0, 1])
        #expect(routine.sortedGroups[1].sortedExercises.map { $0.exercise?.name } == ["B"])
        #expect(superset.isSuperset)
    }

    @Test("A solo exercise merges into the group above, at the end")
    func mergeSoloUp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let top = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExercise(makeExercise("B", in: context), to: top, context: context)
        let solo = routine.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        routine.mergeSoloGroup(solo, direction: -1, context: context)

        #expect(routine.sortedGroups.count == 1)
        #expect(top.sortedExercises.map { $0.exercise?.name } == ["A", "B", "C"])
        #expect(top.sortedExercises.map(\.order) == [0, 1, 2])
    }

    @Test("A solo exercise merges into the group below, at the front")
    func mergeSoloDown() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let solo = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        let bottom = routine.addExerciseInNewGroup(makeExercise("B", in: context), context: context)
        routine.addExercise(makeExercise("C", in: context), to: bottom, context: context)

        routine.mergeSoloGroup(solo, direction: 1, context: context)

        #expect(routine.sortedGroups.count == 1)
        #expect(bottom.sortedExercises.map { $0.exercise?.name } == ["A", "B", "C"])
    }

    @Test("Merging refuses supersets and missing neighbors")
    func mergeGuards() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let pair = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExercise(makeExercise("B", in: context), to: pair, context: context)
        let solo = routine.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        routine.mergeSoloGroup(pair, direction: 1, context: context)   // superset: refused
        routine.mergeSoloGroup(solo, direction: 1, context: context)   // no neighbor below: refused

        #expect(routine.sortedGroups.count == 2)
        #expect(pair.sortedExercises.count == 2)
        #expect(solo.sortedExercises.count == 1)
    }
}

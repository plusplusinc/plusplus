import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Superset mutations")
struct SupersetTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self, WorkoutExercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
        let workout = Workout(name: "PT")
        context.insert(workout)

        let first = workout.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        let second = workout.addExerciseInNewGroup(makeExercise("T Raise", in: context), context: context)

        #expect(workout.sortedGroups.count == 2)
        #expect(workout.sortedGroups[0] === first)
        #expect(workout.sortedGroups[1] === second)
        #expect(workout.sortedGroups.map(\.order) == [0, 1])
        #expect(!first.isSuperset)
    }

    @Test("Adding to an existing group forms a superset in order")
    func addToGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let group = workout.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        workout.addExercise(makeExercise("T Raise", in: context), to: group, context: context)

        #expect(group.isSuperset)
        #expect(group.sortedExercises.count == 2)
        #expect(group.sortedExercises.map(\.order) == [0, 1])
        #expect(group.sortedExercises.map { $0.exercise?.name } == ["Y Raise", "T Raise"])
        #expect(workout.sortedGroups.count == 1)
    }

    @Test("Splitting moves the exercise into its own group right after")
    func splitExercise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let superset = workout.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        superset.sets = 4
        workout.addExercise(makeExercise("T Raise", in: context), to: superset, context: context)
        let trailing = workout.addExerciseInNewGroup(makeExercise("Band Pulses", in: context), context: context)

        let tRaise = superset.sortedExercises[1]
        workout.splitExercise(tRaise, context: context)

        let groups = workout.sortedGroups
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
        let workout = Workout(name: "PT")
        context.insert(workout)

        let group = workout.addExerciseInNewGroup(makeExercise("Y Raise", in: context), context: context)
        let solo = group.sortedExercises[0]
        workout.splitExercise(solo, context: context)

        #expect(workout.sortedGroups.count == 1)
        #expect(solo.group === group)
    }

    @Test("Three-exercise superset splits cleanly from the middle")
    func splitFromMiddle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let superset = workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        workout.addExercise(makeExercise("B", in: context), to: superset, context: context)
        workout.addExercise(makeExercise("C", in: context), to: superset, context: context)

        let middle = superset.sortedExercises[1]
        workout.splitExercise(middle, context: context)

        #expect(superset.sortedExercises.map { $0.exercise?.name } == ["A", "C"])
        #expect(superset.sortedExercises.map(\.order) == [0, 1])
        #expect(workout.sortedGroups[1].sortedExercises.map { $0.exercise?.name } == ["B"])
        #expect(superset.isSuperset)
    }
}

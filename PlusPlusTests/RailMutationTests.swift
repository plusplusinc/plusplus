import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The Workout mutations behind the #78 rail gestures: gap drops,
/// in-ring reorders, and the directional split the ring's top edge uses.
@Suite("Rail gesture mutations")
struct RailMutationTests {
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

    private func names(of workout: Workout) -> [[String]] {
        workout.sortedGroups.map { group in
            group.sortedExercises.map { $0.exercise?.name ?? "?" }
        }
    }

    @Test("A solo drop to a later gap moves the whole group")
    func soloMovesDown() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let a = workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        workout.addExerciseInNewGroup(makeExercise("B", in: context), context: context)
        workout.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        // Gap 2 = between B and C.
        workout.placeSolo(a.sortedExercises[0], atGap: 2, context: context)

        #expect(names(of: workout) == [["B"], ["A"], ["C"]])
        #expect(workout.sortedGroups.map(\.order) == [0, 1, 2])
    }

    @Test("A solo drop to an earlier gap moves the whole group")
    func soloMovesUp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        workout.addExerciseInNewGroup(makeExercise("B", in: context), context: context)
        let c = workout.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        workout.placeSolo(c.sortedExercises[0], atGap: 0, context: context)

        #expect(names(of: workout) == [["C"], ["A"], ["B"]])
    }

    @Test("Dropping into an adjacent gap is a no-op")
    func adjacentGapsAreNoOps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let a = workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        workout.addExerciseInNewGroup(makeExercise("B", in: context), context: context)

        workout.placeSolo(a.sortedExercises[0], atGap: 0, context: context)
        #expect(names(of: workout) == [["A"], ["B"]])
        workout.placeSolo(a.sortedExercises[0], atGap: 1, context: context)
        #expect(names(of: workout) == [["A"], ["B"]])
    }

    @Test("A member dropped in a gap leaves the ring and lands solo")
    func memberLeavesRing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let superset = workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        superset.sets = 4
        workout.addExercise(makeExercise("B", in: context), to: superset, context: context)
        workout.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        // Drag B to the very end (gap 2 in pre-move indices).
        workout.placeSolo(superset.sortedExercises[1], atGap: 2, context: context)

        #expect(names(of: workout) == [["A"], ["C"], ["B"]])
        #expect(workout.sortedGroups[2].sets == 4, "extracted member keeps the ring's set count")
        #expect(!superset.isSuperset)
    }

    @Test("Reordering within a group shuffles members and orders")
    func reorderWithinGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let superset = workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        workout.addExercise(makeExercise("B", in: context), to: superset, context: context)
        workout.addExercise(makeExercise("C", in: context), to: superset, context: context)

        workout.reorderExercise(superset.sortedExercises[0], toIndex: 2)

        #expect(superset.sortedExercises.map { $0.exercise?.name } == ["B", "C", "A"])
        #expect(superset.sortedExercises.map(\.order) == [0, 1, 2])
        #expect(workout.sortedGroups.count == 1)
    }

    @Test("Split with placeAbove lands the member before the ring")
    func splitAboveForTopEdge() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        workout.addExerciseInNewGroup(makeExercise("Lead", in: context), context: context)
        let superset = workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        workout.addExercise(makeExercise("B", in: context), to: superset, context: context)

        workout.splitExercise(superset.sortedExercises[0], placeAbove: true, context: context)

        #expect(names(of: workout) == [["Lead"], ["A"], ["B"]])
        #expect(workout.sortedGroups.map(\.order) == [0, 1, 2])
    }

    @Test("Ring commit loop: absorb two solos below, then eject one")
    func ringCommitComposition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "PT")
        context.insert(workout)

        let superset = workout.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        workout.addExercise(makeExercise("B", in: context), to: superset, context: context)
        workout.addExerciseInNewGroup(makeExercise("C", in: context), context: context)
        workout.addExerciseInNewGroup(makeExercise("D", in: context), context: context)

        // Extend the bottom edge over both solos, the way the view
        // commits a RingSpan(absorbAfter: 2).
        for _ in 0..<2 {
            let groups = workout.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === superset }),
                  groups.indices.contains(index + 1) else { break }
            workout.mergeSoloGroup(groups[index + 1], direction: -1, context: context)
        }
        #expect(names(of: workout) == [["A", "B", "C", "D"]])

        // Then contract by one (ejectLast: 1).
        workout.splitExercise(superset.sortedExercises[3], context: context)
        #expect(names(of: workout) == [["A", "B", "C"], ["D"]])
    }
}

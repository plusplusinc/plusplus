import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The Routine mutations behind the #78 rail gestures: gap drops,
/// in-ring reorders, and the directional split the ring's top edge uses.
@Suite("Rail gesture mutations")
struct RailMutationTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeExercise(_ name: String, in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: .shoulders)
        context.insert(exercise)
        return exercise
    }

    private func names(of routine: Routine) -> [[String]] {
        routine.sortedGroups.map { group in
            group.sortedExercises.map { $0.exercise?.name ?? "?" }
        }
    }

    @Test("A solo drop to a later gap moves the whole group")
    func soloMovesDown() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let a = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExerciseInNewGroup(makeExercise("B", in: context), context: context)
        routine.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        // Gap 2 = between B and C.
        routine.placeSolo(a.sortedExercises[0], atGap: 2, context: context)

        #expect(names(of: routine) == [["B"], ["A"], ["C"]])
        #expect(routine.sortedGroups.map(\.order) == [0, 1, 2])
    }

    @Test("A solo drop to an earlier gap moves the whole group")
    func soloMovesUp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExerciseInNewGroup(makeExercise("B", in: context), context: context)
        let c = routine.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        routine.placeSolo(c.sortedExercises[0], atGap: 0, context: context)

        #expect(names(of: routine) == [["C"], ["A"], ["B"]])
    }

    @Test("Dropping into an adjacent gap is a no-op")
    func adjacentGapsAreNoOps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let a = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExerciseInNewGroup(makeExercise("B", in: context), context: context)

        routine.placeSolo(a.sortedExercises[0], atGap: 0, context: context)
        #expect(names(of: routine) == [["A"], ["B"]])
        routine.placeSolo(a.sortedExercises[0], atGap: 1, context: context)
        #expect(names(of: routine) == [["A"], ["B"]])
    }

    @Test("A member dropped in a gap leaves the ring and lands solo")
    func memberLeavesRing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let superset = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        superset.sets = 4
        routine.addExercise(makeExercise("B", in: context), to: superset, context: context)
        routine.addExerciseInNewGroup(makeExercise("C", in: context), context: context)

        // Drag B to the very end (gap 2 in pre-move indices).
        routine.placeSolo(superset.sortedExercises[1], atGap: 2, context: context)

        #expect(names(of: routine) == [["A"], ["C"], ["B"]])
        #expect(routine.sortedGroups[2].sets == 4, "extracted member keeps the ring's set count")
        #expect(!superset.isSuperset)
    }

    @Test("Reordering within a group shuffles members and orders")
    func reorderWithinGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let superset = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExercise(makeExercise("B", in: context), to: superset, context: context)
        routine.addExercise(makeExercise("C", in: context), to: superset, context: context)

        routine.reorderExercise(superset.sortedExercises[0], toIndex: 2)

        #expect(superset.sortedExercises.map { $0.exercise?.name } == ["B", "C", "A"])
        #expect(superset.sortedExercises.map(\.order) == [0, 1, 2])
        #expect(routine.sortedGroups.count == 1)
    }

    @Test("Split with placeAbove lands the member before the ring")
    func splitAboveForTopEdge() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        routine.addExerciseInNewGroup(makeExercise("Lead", in: context), context: context)
        let superset = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExercise(makeExercise("B", in: context), to: superset, context: context)

        routine.splitExercise(superset.sortedExercises[0], placeAbove: true, context: context)

        #expect(names(of: routine) == [["Lead"], ["A"], ["B"]])
        #expect(routine.sortedGroups.map(\.order) == [0, 1, 2])
    }

    @Test("Ring commit loop: absorb two solos below, then eject one")
    func ringCommitComposition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "PT")
        context.insert(routine)

        let superset = routine.addExerciseInNewGroup(makeExercise("A", in: context), context: context)
        routine.addExercise(makeExercise("B", in: context), to: superset, context: context)
        routine.addExerciseInNewGroup(makeExercise("C", in: context), context: context)
        routine.addExerciseInNewGroup(makeExercise("D", in: context), context: context)

        // Extend the bottom edge over both solos, the way the view
        // commits a RingSpan(absorbAfter: 2).
        for _ in 0..<2 {
            let groups = routine.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === superset }),
                  groups.indices.contains(index + 1) else { break }
            routine.mergeSoloGroup(groups[index + 1], direction: -1, context: context)
        }
        #expect(names(of: routine) == [["A", "B", "C", "D"]])

        // Then contract by one (ejectLast: 1).
        routine.splitExercise(superset.sortedExercises[3], context: context)
        #expect(names(of: routine) == [["A", "B", "C"], ["D"]])
    }
}

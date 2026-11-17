import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// The session's list of exercises, and the order it stores a created one in. A relaunch is a
/// second store over the same container: it sees only what landed.
@Suite("Routine session exercises")
struct RoutineSessionExerciseTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    @Test("A created exercise is stored before the routine save that names it, and listed at once")
    func createdBeforeRow() async throws {
        let session = RoutineSession(
            routine: Routine(),
            store: relaunch(),
            namer: .muscleGroupsOnly,
        )
        let created = CreatedExercise(name: "Ring row with rotation", muscleGroups: [.back])
        let exercise = await session.create(created)
        #expect(session.exercises.exercise(id: created.id) == exercise)
        // Stored once `create` returns, before any routine save could name it.
        #expect(try await relaunch().exercises().exercise(id: created.id) == exercise)
        let routine = Routine(exercises: [RoutineExercise(exercise: exercise, weightUnit: .pounds)])
        session.save(routine)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }
}

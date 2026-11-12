import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// The order the session sends its writes in. A relaunch is a second store over the same
/// container: it sees only what landed.
@Suite("Routine session")
struct RoutineSessionTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private func session(_ routine: Routine = Routine()) -> RoutineSession {
        RoutineSession(routine: routine, store: relaunch())
    }

    private static func upper() throws -> Routine {
        let bench = try RoutineExercise.builtIn("Barbell bench press")
        return Routine(name: "Upper", exercises: [bench])
    }

    @Test("An edit just before a switch is saved before the next routine opens")
    func editBeforeSwitch() async throws {
        let session = session()
        let routine = try Self.upper()
        session.save(routine)
        await session.startNew()
        #expect(session.current.isEmpty)
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }
}

extension RoutineExercise {
    /// A row of the built-in exercise named `name`, its default plan changed by `edit`.
    static func builtIn(
        _ name: String,
        _ edit: (inout ExercisePlan) -> Void = { _ in },
    ) throws -> RoutineExercise {
        let exercise = try #require(Exercise.builtIn.first { $0.name == name })
        var plan = exercise.defaultPlan(in: .pounds)
        edit(&plan)
        return RoutineExercise(exercise: exercise, plan: plan)
    }
}

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

    /// A session open on a routine with a row of a created exercise and a push-up, its last
    /// edit not yet landed, and another saved routine using the exercise.
    private func sessionUsing(
        _ created: CreatedExercise,
    ) async throws -> (RoutineSession, other: Routine) {
        let store = relaunch()
        try await store.save(created)
        let row = RoutineExercise(exercise: Exercise(created: created), weightUnit: .pounds)
        let other = Routine(name: "Other", exercises: [row])
        try await store.save(other, at: Date(timeIntervalSinceReferenceDate: 1))
        let open = Routine(name: "Open", exercises: [row])
        let session = try await RoutineSession(
            routine: open,
            exercises: store.exercises(),
            store: store,
            namer: .muscleGroupsOnly,
        )
        await session.refreshRecent(weightUnit: .pounds)
        var edited = open
        let pushUp = try #require(Exercise.builtIn(id: "push-up"))
        edited.exercises.append(RoutineExercise(exercise: pushUp, weightUnit: .pounds))
        session.save(edited)
        return (session, other)
    }

    @Test("A customize reaches the open routine and the saved ones, its last edit kept")
    func customizeReachesOpen() async throws {
        let created = CreatedExercise(name: "Cable curl", muscleGroups: [.arms])
        let (session, other) = try await sessionUsing(created)
        #expect(session.routines(using: created.id).map(\.name) == ["Open", "Other"])
        var renamed = created
        renamed.name = "Hammer curl"
        await session.customize(renamed.id, to: renamed.settings, weightUnit: .pounds)
        #expect(session.exercises.created(id: created.id) == renamed)
        #expect(session.current.exercises.map(\.exercise.name) == ["Hammer curl", "Push-up"])
        let saved = try #require(session.recent.first { $0.id == other.id })
        #expect(saved.exercises.map(\.exercise.name) == ["Hammer curl"])
    }

    @Test("A built-in's customize and its clear reach the open routine and the saved ones")
    func builtInCustomizeAndClear() async throws {
        let store = relaunch()
        let bench = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let row = RoutineExercise(exercise: bench, weightUnit: .pounds)
        let other = Routine(name: "Other", exercises: [row])
        try await store.save(other, at: Date(timeIntervalSinceReferenceDate: 1))
        let open = Routine(name: "Open", exercises: [row])
        let session = RoutineSession(routine: open, store: store, namer: .muscleGroupsOnly)
        // Not yet landed as the customize starts.
        session.save(open)
        await session.refreshRecent(weightUnit: .pounds)
        var settings = bench.settings
        settings.name = "Bench press"
        await session.customize(bench.id, to: settings, weightUnit: .pounds)
        #expect(session.exercises.customization(id: bench.id)?.changed == [.name])
        #expect(session.current.exercises.map(\.exercise.name) == ["Bench press"])
        let saved = try #require(session.recent.first { $0.id == other.id })
        #expect(saved.exercises.map(\.exercise.name) == ["Bench press"])
        #expect(try await relaunch().exercises().exercise(id: bench.id)?.name == "Bench press")

        await session.clearCustomizations(bench.id, weightUnit: .pounds)
        #expect(session.exercises == .builtIn)
        #expect(session.current.exercises.map(\.exercise) == [bench])
        let cleared = try #require(session.recent.first { $0.id == other.id })
        #expect(cleared.exercises.map(\.exercise) == [bench])
        #expect(try await relaunch().exercises() == .builtIn)
    }

    @Test("A delete takes the exercise's rows from the open routine and the saved ones")
    func deleteReachesOpen() async throws {
        let created = CreatedExercise(name: "Cable curl", muscleGroups: [.arms])
        let (session, other) = try await sessionUsing(created)
        await session.deleteExercise(created.id, weightUnit: .pounds)
        #expect(session.exercises == .builtIn)
        #expect(session.current.exercises.map(\.exercise.name) == ["Push-up"])
        #expect(session.routines(using: created.id).isEmpty)
        let saved = try #require(session.recent.first { $0.id == other.id })
        #expect(saved.exercises.isEmpty)
    }

    @Test("The open routine uses an exercise while it has a row of it, and not once deleted")
    func openRoutineUsesUntilDeleted() async throws {
        let created = CreatedExercise(name: "Cable curl", muscleGroups: [.arms])
        let (session, _) = try await sessionUsing(created)
        #expect(session.openRoutineUses(created.id))
        #expect(!session.openRoutineUses("push-up-unused"))
        await session.deleteExercise(created.id, weightUnit: .pounds)
        #expect(!session.openRoutineUses(created.id))
    }

    @Test("A change that can't be stored leaves the list as it was")
    func unstoredChangeListsNothing() async {
        let session = RoutineSession(routine: Routine(), store: nil, namer: .muscleGroupsOnly)
        let created = CreatedExercise(name: "Cable curl", muscleGroups: [.arms])
        _ = await session.create(created)
        var renamed = created
        renamed.name = "Hammer curl"
        await session.customize(renamed.id, to: renamed.settings, weightUnit: .pounds)
        #expect(session.exercises.created(id: created.id) == created)
        await session.deleteExercise(created.id, weightUnit: .pounds)
        #expect(session.exercises.created(id: created.id) == created)
    }
}

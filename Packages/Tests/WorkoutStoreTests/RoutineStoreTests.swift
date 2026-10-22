import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved.
@Suite("Routine store")
struct RoutineStoreTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private func count<Model: PersistentModel>(_: Model.Type) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<Model>())
    }

    private static func row(_ name: String) throws -> RoutineExercise {
        try RoutineExercise(exercise: Exercise.builtIn(named: name), weightUnit: .pounds)
    }

    @Test("An untouched store opens nothing")
    func untouched() async throws {
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == nil)
        #expect(try count(StoredRoutine.self) == 0)
    }

    @Test("A new routine with nothing in it is never stored")
    func emptyNotStored() async throws {
        try await relaunch().save(Routine())
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == nil)
        #expect(try count(StoredRoutine.self) == 0)
    }

    @Test("A named routine with no exercises reopens")
    func namedReopens() async throws {
        let routine = Routine(name: "Arm and back day")
        try await relaunch().save(routine)
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }

    @Test("Rows reopen in order, duplicates and ids kept")
    func rowsReopen() async throws {
        let pullUp = try Self.row("Pull-up")
        let routine = try Routine(
            exercises: [Self.row("Barbell bench press"), pullUp, Self.row("Pull-up")],
        )
        try await relaunch().save(routine)
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }

    @Test("A deleted row stays deleted, the rest in order, with no row left behind")
    func deletedRow() async throws {
        let store = relaunch()
        var routine = try Routine(exercises: [
            Self.row("Push-up"), Self.row("Plank"), Self.row("Pull-up"),
        ])
        try await store.save(routine)
        routine.exercises.remove(at: 1)
        try await store.save(routine)

        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
        #expect(try count(StoredRoutineExercise.self) == 2)
    }

    @Test("A reordered routine reopens in its new order")
    func reorderedReopens() async throws {
        let store = relaunch()
        let last = try Self.row("Pull-up")
        var routine = try Routine(exercises: [Self.row("Push-up"), Self.row("Plank"), last])
        try await store.save(routine)
        let first = try #require(routine.exercises.first)
        routine.move(last.id, to: .before(first.id))
        try await store.save(routine)

        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
        #expect(try count(StoredRoutineExercise.self) == 3)
    }

    @Test("A routine cleared to nothing is deleted, rows and all")
    func clearedIsDeleted() async throws {
        let store = relaunch()
        var routine = try Routine(name: "Legs", exercises: [Self.row("Goblet squat")])
        try await store.save(routine)
        routine.name = ""
        routine.exercises = []
        try await store.save(routine)

        #expect(try await relaunch().launch(weightUnit: .pounds).routine == nil)
        #expect(try count(StoredRoutine.self) == 0)
        #expect(try count(StoredRoutineExercise.self) == 0)
    }

    @Test("The routine edited last is the one that opens")
    func latestEditedOpens() async throws {
        let store = relaunch()
        let older = Routine(name: "Older")
        var newer = Routine(name: "Newer")
        try await store.save(newer, at: Date(timeIntervalSince1970: 200))
        try await store.save(older, at: Date(timeIntervalSince1970: 100))
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == newer)

        var renamed = older
        renamed.name = "Renamed"
        try await store.save(renamed, at: Date(timeIntervalSince1970: 300))
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == renamed)
    }

    @Test("A row whose exercise isn't built in is dropped, and the rest load")
    func unknownExerciseDropped() async throws {
        let plank = try Self.row("Plank")
        try await relaunch().save(Routine(exercises: [plank]))
        let context = ModelContext(container)
        let stored = try #require(try context.fetch(FetchDescriptor<StoredRoutine>()).first)
        let unknown = StoredRoutineExercise(id: UUID(), exerciseID: "not-built-in", position: 1)
        context.insert(unknown)
        unknown.routine = stored
        try context.save()

        #expect(try await relaunch().launch(weightUnit: .pounds).routine?.exercises == [plank])
    }

    @Test("A routine is empty with no name and no rows")
    func isEmpty() throws {
        #expect(Routine().isEmpty)
        #expect(!Routine(name: "Legs").isEmpty)
        #expect(try !Routine(exercises: [Self.row("Plank")]).isEmpty)
    }
}

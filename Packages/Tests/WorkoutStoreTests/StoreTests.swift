import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved.
@Suite("Workout store")
struct StoreTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private func count<Model: PersistentModel>(_: Model.Type) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<Model>())
    }

    private static func row(_ name: String) throws -> WorkoutExercise {
        try WorkoutExercise(exercise: Exercise.builtIn(named: name), weightUnit: .pounds)
    }

    @Test("An untouched store opens nothing")
    func untouched() async throws {
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == nil)
        #expect(try count(StoredRoutine.self) == 0)
    }

    @Test("A new workout with nothing in it is never stored")
    func emptyNotStored() async throws {
        try await relaunch().save(Workout())
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == nil)
        #expect(try count(StoredRoutine.self) == 0)
    }

    @Test("A named workout with no exercises reopens")
    func namedReopens() async throws {
        let workout = Workout(name: "Arm and back day")
        try await relaunch().save(workout)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
    }

    @Test("Rows reopen in order, duplicates and ids kept")
    func rowsReopen() async throws {
        let pullUp = try Self.row("Pull-up")
        let workout = try Workout(
            exercises: [Self.row("Barbell bench press"), pullUp, Self.row("Pull-up")],
        )
        try await relaunch().save(workout)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
    }

    @Test("A deleted row stays deleted, the rest in order, with no row left behind")
    func deletedRow() async throws {
        let store = relaunch()
        var workout = try Workout(exercises: [
            Self.row("Push-up"), Self.row("Plank"), Self.row("Pull-up"),
        ])
        try await store.save(workout)
        workout.exercises.remove(at: 1)
        try await store.save(workout)

        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
        #expect(try count(StoredRoutineExercise.self) == 2)
    }

    @Test("A reordered workout reopens in its new order")
    func reorderedReopens() async throws {
        let store = relaunch()
        let last = try Self.row("Pull-up")
        var workout = try Workout(exercises: [Self.row("Push-up"), Self.row("Plank"), last])
        try await store.save(workout)
        let first = try #require(workout.exercises.first)
        workout.move(last.id, to: .before(first.id))
        try await store.save(workout)

        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
        #expect(try count(StoredRoutineExercise.self) == 3)
    }

    @Test("A workout cleared to nothing is deleted, rows and all")
    func clearedIsDeleted() async throws {
        let store = relaunch()
        var workout = try Workout(name: "Legs", exercises: [Self.row("Goblet squat")])
        try await store.save(workout)
        workout.name = ""
        workout.exercises = []
        try await store.save(workout)

        #expect(try await relaunch().launch(weightUnit: .pounds).workout == nil)
        #expect(try count(StoredRoutine.self) == 0)
        #expect(try count(StoredRoutineExercise.self) == 0)
    }

    @Test("The workout edited last is the one that opens")
    func latestEditedOpens() async throws {
        let store = relaunch()
        let older = Workout(name: "Older")
        var newer = Workout(name: "Newer")
        try await store.save(newer, at: Date(timeIntervalSince1970: 200))
        try await store.save(older, at: Date(timeIntervalSince1970: 100))
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == newer)

        var renamed = older
        renamed.name = "Renamed"
        try await store.save(renamed, at: Date(timeIntervalSince1970: 300))
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == renamed)
    }

    @Test("A row whose exercise isn't built in is dropped, and the rest load")
    func unknownExerciseDropped() async throws {
        let plank = try Self.row("Plank")
        try await relaunch().save(Workout(exercises: [plank]))
        let context = ModelContext(container)
        let stored = try #require(try context.fetch(FetchDescriptor<StoredRoutine>()).first)
        let unknown = StoredRoutineExercise(id: UUID(), exerciseID: "not-built-in", position: 1)
        context.insert(unknown)
        unknown.routine = stored
        try context.save()

        #expect(try await relaunch().launch(weightUnit: .pounds).workout?.exercises == [plank])
    }

    @Test("A workout is empty with no name and no rows")
    func isEmpty() throws {
        #expect(Workout().isEmpty)
        #expect(!Workout(name: "Legs").isEmpty)
        #expect(try !Workout(exercises: [Self.row("Plank")]).isEmpty)
    }
}

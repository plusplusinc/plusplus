import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved. Dates are
/// explicit, so the order never rests on how fast the test runs.
@Suite("Routine store recency")
struct StoreRecencyTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func workout(_ name: String) -> Workout {
        Workout(name: name)
    }

    private func listed() async throws -> [String] {
        try await relaunch().workoutsByRecency(weightUnit: .pounds).map(\.name)
    }

    @Test("Routines list by when they were last opened or edited")
    func listOrder() async throws {
        let store = relaunch()
        let first = Self.workout("A")
        var second = Self.workout("B")
        try await store.save(first, at: Self.at(1))
        try await store.save(second, at: Self.at(2))
        _ = try await store.openWorkout(first.id, weightUnit: .pounds, at: Self.at(3))
        #expect(try await listed() == ["A", "B"])
        second.name = "B again"
        try await store.save(second, at: Self.at(4))
        #expect(try await listed() == ["B again", "A"])
    }

    @Test("Launch reopens the routine opened last")
    func launchOpened() async throws {
        let store = relaunch()
        let first = Self.workout("A")
        try await store.save(first, at: Self.at(1))
        try await store.save(Self.workout("B"), at: Self.at(2))
        _ = try await store.openWorkout(first.id, weightUnit: .pounds, at: Self.at(3))
        #expect(try await relaunch().launch(weightUnit: .pounds).workout?.name == "A")
    }

    @Test("Launch reopens the routine edited last, after an open")
    func launchEditedAfterOpen() async throws {
        let store = relaunch()
        let first = Self.workout("A")
        try await store.save(first, at: Self.at(1))
        _ = try await store.openWorkout(first.id, weightUnit: .pounds, at: Self.at(3))
        try await store.save(Self.workout("B"), at: Self.at(4))
        #expect(try await relaunch().launch(weightUnit: .pounds).workout?.name == "B")
    }

    @Test("Launch opens the routine listed first, whatever ties")
    func launchMatchesList() async throws {
        let store = relaunch()
        for name in ["A", "B", "C", "D"] {
            try await store.save(Self.workout(name), at: Self.at(1))
        }
        let first = try await listed().first
        #expect(try await relaunch().launch(weightUnit: .pounds).workout?.name == first)
    }

    @Test("Opening a routine returns it whole: name, rows, plans, and supersets")
    func openReturnsWhole() async throws {
        let rows = try ["Push-up", "Plank", "Pull-up"].map { try WorkoutExercise.builtIn($0) }
        var workout = Workout(name: "Whole", exercises: rows)
        workout.exercises[0].plan.sets = 5
        workout = try #require(workout.regrouped(holding: rows[1].id, reaching: rows[2].id))
            .workout
        try await relaunch().save(workout, at: Self.at(1))
        let opened = try await relaunch()
            .openWorkout(workout.id, weightUnit: .pounds, at: Self.at(2))
        #expect(opened == workout)
    }

    @Test("Opening an unknown routine stores nothing")
    func openUnknown() async throws {
        try await relaunch().save(Self.workout("A"), at: Self.at(1))
        #expect(try await relaunch().openWorkout(UUID(), weightUnit: .pounds) == nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredRoutine>()) == 1)
    }

    @Test("An untouched routine never lists")
    func untouchedNeverLists() async throws {
        try await relaunch().save(Workout())
        #expect(try await listed().isEmpty)
    }

    @Test("Every saved routine lists, not just five")
    func everyWorkoutLists() async throws {
        let store = relaunch()
        let names = (1 ... 7).map { "R\($0)" }
        for (index, name) in names.enumerated() {
            try await store.save(Self.workout(name), at: Self.at(TimeInterval(index)))
        }
        #expect(try await listed() == names.reversed())
    }

    @Test("The open routine comes first, as it is now")
    func withOpen() {
        let first = Self.workout("A")
        var second = Self.workout("B")
        let third = Self.workout("C")
        let stored = [first, second, third]
        second.name = "B edited"
        #expect(stored.withOpen(second).map(\.name) == ["B edited", "A", "C"])
        #expect(stored.withOpen(Workout()).map(\.name) == ["A", "B", "C"])
    }

    @Test("A list holds the order it was drawn in, as the routines change")
    func heldOrder() {
        let first = Self.workout("A")
        var second = Self.workout("B")
        let third = Self.workout("C")
        let order = [first, second, third].map(\.id)
        second.name = "B edited"
        // B was opened, so it is now first; the list keeps showing it where it was.
        #expect([second, first, third].held(in: order).map(\.name) == ["A", "B edited", "C"])
        // One gone drops out, and the rest keep their places.
        #expect([third, first].held(in: order).map(\.name) == ["A", "C"])
    }

    @Test("A routine the order hasn't seen goes first, in its place among the new")
    func heldNewFirst() {
        let old = Self.workout("Old")
        let order = [old.id]
        let newer = Self.workout("Newer")
        let newest = Self.workout("Newest")
        #expect([newest, newer, old].held(in: order).map(\.name) == ["Newest", "Newer", "Old"])
        // Read before the saved routines arrived, the order holds only the open one.
        #expect([old, newer, newest].held(in: order).map(\.name) == ["Newer", "Newest", "Old"])
    }
}

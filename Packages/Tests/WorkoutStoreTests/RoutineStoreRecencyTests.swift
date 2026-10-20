import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved. Dates are
/// explicit, so the order never rests on how fast the test runs.
@Suite("Routine store recency")
struct RoutineStoreRecencyTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func routine(_ name: String) -> Routine {
        Routine(name: name)
    }

    private func listed() async throws -> [String] {
        try await relaunch().routinesByRecency(weightUnit: .pounds).map(\.name)
    }

    @Test("Routines list by when they were last opened or edited")
    func listOrder() async throws {
        let store = relaunch()
        let first = Self.routine("A")
        var second = Self.routine("B")
        try await store.save(first, at: Self.at(1))
        try await store.save(second, at: Self.at(2))
        _ = try await store.openRoutine(first.id, weightUnit: .pounds, at: Self.at(3))
        #expect(try await listed() == ["A", "B"])
        second.name = "B again"
        try await store.save(second, at: Self.at(4))
        #expect(try await listed() == ["B again", "A"])
    }

    @Test("Launch reopens the routine opened last")
    func launchOpened() async throws {
        let store = relaunch()
        let first = Self.routine("A")
        try await store.save(first, at: Self.at(1))
        try await store.save(Self.routine("B"), at: Self.at(2))
        _ = try await store.openRoutine(first.id, weightUnit: .pounds, at: Self.at(3))
        #expect(try await relaunch().launchRoutine(weightUnit: .pounds)?.name == "A")
    }

    @Test("Launch reopens the routine edited last, after an open")
    func launchEditedAfterOpen() async throws {
        let store = relaunch()
        let first = Self.routine("A")
        try await store.save(first, at: Self.at(1))
        _ = try await store.openRoutine(first.id, weightUnit: .pounds, at: Self.at(3))
        try await store.save(Self.routine("B"), at: Self.at(4))
        #expect(try await relaunch().launchRoutine(weightUnit: .pounds)?.name == "B")
    }

    @Test("Launch opens the routine listed first, whatever ties")
    func launchMatchesList() async throws {
        let store = relaunch()
        for name in ["A", "B", "C", "D"] {
            try await store.save(Self.routine(name), at: Self.at(1))
        }
        let first = try await listed().first
        #expect(try await relaunch().launchRoutine(weightUnit: .pounds)?.name == first)
    }

    @Test("Opening a routine returns it whole: name, rows, plans, and supersets")
    func openReturnsWhole() async throws {
        let rows = try ["Push-up", "Plank", "Pull-up"].map { try RoutineExercise.builtIn($0) }
        var routine = Routine(name: "Whole", exercises: rows)
        routine.exercises[0].plan.sets = 5
        routine = try #require(routine.regrouped(holding: rows[1].id, reaching: rows[2].id))
            .routine
        try await relaunch().save(routine, at: Self.at(1))
        let opened = try await relaunch()
            .openRoutine(routine.id, weightUnit: .pounds, at: Self.at(2))
        #expect(opened == routine)
    }

    @Test("Opening an unknown routine stores nothing")
    func openUnknown() async throws {
        try await relaunch().save(Self.routine("A"), at: Self.at(1))
        #expect(try await relaunch().openRoutine(UUID(), weightUnit: .pounds) == nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredRoutine>()) == 1)
    }

    @Test("An untouched routine never lists")
    func untouchedNeverLists() async throws {
        try await relaunch().save(Routine())
        #expect(try await listed().isEmpty)
    }

    @Test("Every saved routine lists, not just five")
    func everyRoutineLists() async throws {
        let store = relaunch()
        let names = (1 ... 7).map { "R\($0)" }
        for (index, name) in names.enumerated() {
            try await store.save(Self.routine(name), at: Self.at(TimeInterval(index)))
        }
        #expect(try await listed() == names.reversed())
    }

    @Test("The open routine comes first, as it is now")
    func withOpen() {
        let first = Self.routine("A")
        var second = Self.routine("B")
        let third = Self.routine("C")
        let stored = [first, second, third]
        second.name = "B edited"
        #expect(stored.withOpen(second).map(\.name) == ["B edited", "A", "C"])
        #expect(stored.withOpen(Routine()).map(\.name) == ["A", "B", "C"])
    }

    @Test("A list holds the order it was drawn in, as the routines change")
    func heldOrder() {
        let first = Self.routine("A")
        var second = Self.routine("B")
        let third = Self.routine("C")
        let order = [first, second, third].map(\.id)
        second.name = "B edited"
        // B was opened, so it is now first; the list keeps showing it where it was.
        #expect([second, first, third].held(in: order).map(\.name) == ["A", "B edited", "C"])
        // One gone drops out, and the rest keep their places.
        #expect([third, first].held(in: order).map(\.name) == ["A", "C"])
    }

    @Test("A routine the order hasn't seen goes first, in its place among the new")
    func heldNewFirst() {
        let old = Self.routine("Old")
        let order = [old.id]
        let newer = Self.routine("Newer")
        let newest = Self.routine("Newest")
        #expect([newest, newer, old].held(in: order).map(\.name) == ["Newest", "Newer", "Old"])
        // Read before the saved routines arrived, the order holds only the open one.
        #expect([old, newer, newest].held(in: order).map(\.name) == ["Newer", "Newest", "Old"])
    }

    @Test("The drawer's three: the latest, the open one first, held as the drawer opened")
    func drawerThree() {
        let saved = (1 ... 5).map { Self.routine("R\($0)") }
        let open = saved[3]
        let recent = saved.withOpen(open)
        let order = recent.map(\.id)
        #expect(recent.held(in: order).prefix(3).map(\.name) == ["R4", "R1", "R2"])
        // Tapping R2 opens it; the drawer, sliding shut, still draws the order it opened with.
        let opened = saved.withOpen(saved[1])
        #expect(opened.held(in: order).prefix(3).map(\.name) == ["R4", "R1", "R2"])
        // Opened again, it takes the order anew.
        #expect(opened.held(in: opened.map(\.id)).prefix(3).map(\.name) == ["R2", "R1", "R3"])
    }
}

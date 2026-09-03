import SwiftData
import Testing
@testable import WorkoutStore

/// A throwaway model so the container can be exercised without the app having a data model yet.
@Model
final class ProbeItem {
    var label: String = ""

    init(label: String) {
        self.label = label
    }
}

@Suite("Store container")
struct WorkoutStoreContainerTests {
    private static let schema = Schema([ProbeItem.self])

    @Test("An in-memory container round-trips a model")
    func inMemoryRoundTrip() throws {
        let container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Self.schema)
        let context = ModelContext(container)
        context.insert(ProbeItem(label: "probe"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ProbeItem>())
        #expect(fetched.map(\.label) == ["probe"])
    }

    @Test("Each in-memory container is isolated from the last")
    func inMemoryIsNotShared() throws {
        let first = try WorkoutStoreContainer.make(mode: .inMemory, schema: Self.schema)
        let context = ModelContext(first)
        context.insert(ProbeItem(label: "probe"))
        try context.save()

        let second = try WorkoutStoreContainer.make(mode: .inMemory, schema: Self.schema)
        #expect(try ModelContext(second).fetch(FetchDescriptor<ProbeItem>()).isEmpty)
    }
}

import Foundation
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

    /// These strings decide which container on disk the app opens. A mismatch with the
    /// entitlements would not fail to build; it would silently point at a different, empty
    /// database, and the widget and Watch app would never see the user's data.
    @Test("Container identifiers match the app's entitlements")
    func identifiersMatchEntitlements() throws {
        let entitlements = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: Self.entitlementsFile), format: nil,
            ) as? [String: Any],
        )
        let appGroups = entitlements["com.apple.security.application-groups"] as? [String]
        let containers =
            entitlements["com.apple.developer.icloud-container-identifiers"] as? [String]
        #expect(appGroups == [WorkoutStoreContainer.appGroupID])
        #expect(containers == [WorkoutStoreContainer.cloudKitContainerID])
    }

    private static let entitlementsFile = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App/PlusPlus.entitlements")
}

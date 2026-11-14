import XCTest

/// Reading many elements from one snapshot of the app's tree. Reading each one's label or value
/// through its own element resolves its query again, element by element, and on Xcode Cloud a
/// query costs about as much as the app's own wait for what it reads.
@MainActor
extension XCUIApplication {
    /// The elements `matches` picks, in the tree's order, the order a query lists them in, all
    /// from one snapshot.
    func snapshots(
        where matches: (any XCUIElementSnapshot) -> Bool,
    ) -> [any XCUIElementSnapshot] {
        do {
            var found: [any XCUIElementSnapshot] = []
            try Self.collect(matches, in: snapshot(), into: &found)
            return found
        } catch {
            XCTFail("The app's tree couldn't be read: \(error)")
            return []
        }
    }

    /// The elements with the identifier `identifier`, as `snapshots(where:)` reads them.
    func snapshots(identified identifier: String) -> [any XCUIElementSnapshot] {
        snapshots { $0.identifier == identifier }
    }

    private static func collect(
        _ matches: (any XCUIElementSnapshot) -> Bool,
        in snapshot: any XCUIElementSnapshot,
        into found: inout [any XCUIElementSnapshot],
    ) {
        if matches(snapshot) {
            found.append(snapshot)
        }
        for child in snapshot.children {
            collect(matches, in: child, into: &found)
        }
    }
}

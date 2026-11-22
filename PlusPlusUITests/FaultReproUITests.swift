import XCTest

// THROWAWAY: counts RowSwipe body runs at launch. Never committed.
final nonisolated class FaultReproUITests: XCTestCase {
    @MainActor
    func testRepro() {
        let app = XCUIApplication()
        XCTContext.runActivity(named: "STEP launch") { _ in
            app.launchSeeding(
                ["barbell-bench-press", "plank"],
                arguments: ["-reproLogSwipe", "YES"],
            )
            Thread.sleep(forTimeInterval: 1.5)
        }
    }
}

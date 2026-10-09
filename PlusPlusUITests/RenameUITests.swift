import XCTest

/// Renaming through the keyboard: Return has to end editing and keep the name, and an empty name
/// has to fall back to the default. The rules are unit-tested in the package; this checks that a
/// real Return reaches them, which no simulator tool could press.
///
/// `nonisolated` because XCTestCase's initializers are; the test itself drives the UI from the
/// main actor.
final nonisolated class RenameUITests: XCTestCase {
    @MainActor
    func testReturnCommitsAndEmptyRestoresDefault() {
        let app = XCUIApplication()
        app.launch()
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))

        title.tap()
        title.typeText("Legs\n")
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 2),
            "Return should end editing",
        )
        XCTAssertEqual(title.value as? String, "Legs")

        // Editing a chosen name starts with the caret at the end, where the `_` shows it.
        title.tap()
        title.typeText(" day\n")
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 2),
            "Return should end editing",
        )
        XCTAssertEqual(title.value as? String, "Legs day")

        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Legs day".count))
        title.typeText("\n")
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 2),
            "Return should end editing",
        )
        XCTAssertEqual(title.value as? String, "New routine")
    }
}

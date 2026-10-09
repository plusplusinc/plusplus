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

        rename(title, in: app, typing: "Legs\n", expecting: "Legs")
        // Editing a chosen name starts with the caret at the end, where the `_` shows it.
        rename(title, in: app, typing: " day\n", expecting: "Legs day")
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Legs day".count)
        rename(title, in: app, typing: deletes + "\n", expecting: "New routine")
    }

    /// Taps the title, types, and checks that the Return at the end of `text` ended editing and
    /// left `expected` behind.
    @MainActor
    private func rename(
        _ title: XCUIElement,
        in app: XCUIApplication,
        typing text: String,
        expecting expected: String,
        line: UInt = #line,
    ) {
        title.tap()
        title.typeText(text)
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 2),
            "Return should end editing",
            line: line,
        )
        XCTAssertEqual(title.value as? String, expected, line: line)
    }
}

import XCTest

/// The title as VoiceOver sees it. VoiceOver frames the field, so the field has to cover every
/// line of the title it shows, including the default, which is drawn behind an empty field.
///
/// `nonisolated` because XCTestCase's initializers are; the tests drive the UI on the main actor.
final nonisolated class TitleAccessibilityUITests: XCTestCase {
    /// At the largest accessibility size the default wraps to two lines, and the field covers
    /// both, at rest and while editing. A one-line name then shows how tall one line is.
    @MainActor
    func testFieldCoversWrappedDefaultAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))

        let atRest = title.frame.height
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertEqual(title.frame.height, atRest, "The field should keep both lines when editing")

        title.typeText("Legs")
        let oneLine = title.frame.height
        XCTAssertGreaterThan(
            atRest,
            oneLine * 1.9,
            "The field should cover the default's two lines",
        )
    }
}

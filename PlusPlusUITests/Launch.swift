import XCTest

/// Launching into the routine screen, and relaunching into what it saved.
@MainActor
extension XCUIApplication {
    /// The routine's title.
    var title: XCUIElement {
        textFields["Routine name"]
    }

    /// Launches into a new routine, not the one the last test saved, at the text size
    /// `category`, since the simulator keeps the last size it was set to, and with `arguments`
    /// besides. Returns the title once it is up.
    func launchNewRoutine(
        textSize category: String = "UICTContentSizeCategoryL",
        arguments: [String] = [],
    ) -> XCUIElement {
        launchArguments = ["-UIPreferredContentSizeCategoryName", category]
            + ["-resetStore", "YES"] + arguments
        launch()
        XCTAssertTrue(title.appears(within: 10), "No title after launch")
        return title
    }

    /// Quits the way a person does, home then gone, and launches again with the same
    /// arguments, this time into whatever the last launch saved.
    func relaunch() {
        XCUIDevice.shared.press(.home)
        terminate()
        if let reset = launchArguments.firstIndex(of: "-resetStore") {
            launchArguments.removeSubrange(reset ... reset + 1)
        }
        launch()
        XCTAssertTrue(title.appears(within: 10), "No title after relaunch")
    }
}

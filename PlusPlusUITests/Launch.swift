import XCTest

/// Launching into the routine screen, and relaunching into what it saved.
@MainActor
extension XCUIApplication {
    /// The routine's title, a text view, since a name wraps.
    var routineTitle: XCUIElement {
        textViews["Routine name"]
    }

    /// The ++ drawer's title, a button that closes it, there only while the drawer shows.
    var drawerTitle: XCUIElement {
        buttons["PlusPlus"]
    }

    /// Launches into a new routine, not the one the last test saved, at the text size
    /// `category`, since the simulator keeps the last size it was set to, and with `arguments`
    /// besides. Returns the title once it is up. UIKit's animations are off
    /// (`LaunchOptions.turnsOffUIKitAnimations`).
    func launchNewRoutine(
        textSize category: String = "UICTContentSizeCategoryL",
        arguments: [String] = [],
    ) -> XCUIElement {
        launchArguments = ["-UIPreferredContentSizeCategoryName", category]
            + ["-resetStore", "YES", "-noUIKitAnimations", "YES"] + arguments
        launch()
        XCTAssertTrue(routineTitle.appears(within: 10), "No title after launch")
        return routineTitle
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
        XCTAssertTrue(routineTitle.appears(within: 10), "No title after relaunch")
    }

    /// A swipe in from the screen's left edge, which opens the drawer or pops a pushed screen.
    func edgeSwipe() {
        let edge = coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 2, dy: 0))
        edge.press(
            forDuration: 0.05,
            thenDragTo: edge.withOffset(CGVector(dx: 300, dy: 0)),
            withVelocity: .default,
            thenHoldForDuration: 0,
        )
    }
}

/// A workout's controls in the bar.
@MainActor
extension XCUIApplication {
    /// The workout's time key, labeled Pause or Resume, its value the time in words.
    var workoutTime: XCUIElement {
        buttons["workout.time"]
    }

    /// Taps Finish in the bar, and returns the menu's own Finish, once it shows: the Finish
    /// that isn't the bar's.
    func openFinishMenu() -> XCUIElement? {
        let bar = navigationBars.buttons["Finish"]
        let barFrame = bar.frame
        bar.tap()
        XCTAssertTrue(buttons["Discard workout"].appears(), "No menu")
        return buttons.matching(NSPredicate(format: "label == 'Finish'"))
            .allElementsBoundByIndex.first { $0.frame != barFrame }
    }

    /// Ends the workout with Finish, then Discard workout, and waits for Start to come back.
    func discardWorkout() {
        navigationBars.buttons["Finish"].tap()
        buttons["Discard workout"].firstMatch.tap()
        XCTAssertTrue(buttons["Start"].appears(), "Discard left the workout running")
    }
}

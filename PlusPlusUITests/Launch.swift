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
            + ["-resetStore", "YES", "-noUIKitAnimations", "YES", "-seedRest", "0"] + arguments
        launch()
        XCTAssertTrue(routineTitle.appears(within: 10), "No title after launch")
        return routineTitle
    }

    /// Launches into a routine of the built-in exercises `ids`, in order, named `name` or left
    /// for the namer, as `launchNewRoutine` does at `textSize` with `arguments`, and waits for
    /// every row.
    /// Seeding (`-seedExercises`) skips the picker, for a test that doesn't check adding.
    @discardableResult
    func launchSeeding(
        _ ids: [String],
        named name: String? = nil,
        textSize category: String = "UICTContentSizeCategoryL",
        arguments: [String] = [],
    ) -> XCUIElement {
        let named = name.map { ["-seedName", $0] } ?? []
        let title = launchNewRoutine(
            textSize: category,
            arguments: ["-seedExercises", ids.joined(separator: ",")] + named + arguments,
        )
        let count = exerciseCount(becoming: ids.count)
        XCTAssertEqual(count, ids.count, "The seeded rows aren't all in")
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
        XCTAssertTrue(routineTitle.appears(within: 10), "No title after relaunch")
    }

    /// Pushes a new, empty routine with the Routines screen's +, reached through the drawer, as a
    /// launch with `-resetStore` starts on: a test that also needs a seeded routine launches into
    /// that one and comes here, a few taps where a second launch costs 5 to 7 s on Xcode Cloud.
    /// Its back chevron leads to the Routines screen.
    func openNewRoutine() {
        openDrawer(andTap: "Routines")
        pushNewRoutine()
    }

    /// Pushes a new, empty routine with the + of the Routines screen showing.
    func pushNewRoutine() {
        let new = buttons["New routine"]
        XCTAssertTrue(new.appears(), "Routines showed no +")
        new.tap()
        XCTAssertEqual(routineTitle.value(becoming: "New routine"), "New routine")
        XCTAssertEqual(exerciseRows.count, 0, "+ opened a routine with rows")
        // The routine slides in as it is pushed.
        XCTAssertTrue(routineTitle.settles(), "The title kept moving after the push")
    }

    /// Opens the drawer with ++ and taps the place labeled `label` in it.
    func openDrawer(andTap label: String) {
        openDrawer(andTap: label) { }
    }

    /// Opens the drawer with ++, runs `whileOpen` once it has slid in, and taps the place labeled
    /// `label` in it.
    func openDrawer(andTap label: String, whileOpen: () throws -> Void) rethrows {
        buttons["Menu"].tap()
        XCTAssertTrue(drawerTitle.appears(), "++ did not open the drawer")
        // The drawer slides in, and a tap read from a frame mid-slide lands where it is going.
        let place = buttons[label]
        XCTAssertTrue(place.settles(), "\(label) kept moving")
        try whileOpen()
        place.tap()
        XCTAssertTrue(drawerTitle.disappears(), "\(label) did not close the drawer")
    }

    /// Taps the bar's back chevron, on any pushed screen.
    func tapBack() {
        buttons["BackButton"].tap()
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

    /// Swipes a sheet down by its bar, titled `title`, to the screen's foot, which closes it.
    func swipeSheetDown(titled title: String) {
        let bar = navigationBars[title].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bar.press(
            forDuration: 0.05,
            thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)),
            withVelocity: .fast,
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

    /// The key at the bottom while a workout runs, labeled by its role: Log set, Log last set,
    /// Go to current exercise, or Finish workout. Found by its identifier, never by the label
    /// Finish workout, which End's dialog also offers.
    var workoutKey: XCUIElement {
        buttons["workout.key"]
    }

    /// Taps the workout's key once it reads `label` and has stopped moving: a key rises, or
    /// swaps for another, after a role change, and a tap mid-swap does nothing.
    func tapWorkoutKey(reading label: String) {
        let key = workoutKey
        XCTAssertEqual(
            reading(key.label, becoming: label, within: 3),
            label,
            "The key never read \(label)",
        )
        XCTAssertTrue(key.settles(), "The key kept moving")
        key.tap()
    }

    /// End, in the bar while a workout runs.
    var endKey: XCUIElement {
        navigationBars.buttons["End workout"]
    }

    /// Taps End in the bar and waits for its dialog: with a set logged, it offers Finish
    /// workout; with none, it says so and offers only Discard workout.
    func openEndDialog(withSetsLogged isLogged: Bool = false) {
        endKey.tap()
        XCTAssertTrue(buttons["Discard workout"].appears(), "No dialog")
        if isLogged {
            XCTAssertTrue(buttons["Finish workout"].exists, "No Finish with sets logged")
        } else {
            XCTAssertFalse(buttons["Finish workout"].exists, "Finish offered with no set done")
            XCTAssertTrue(staticTexts["Nothing has been logged yet."].exists, "No message")
        }
    }

    /// Ends the workout with End, then Discard workout, and waits for Start to come back.
    func discardWorkout(withSetsLogged isLogged: Bool = false) {
        openEndDialog(withSetsLogged: isLogged)
        buttons["Discard workout"].firstMatch.tap()
        XCTAssertTrue(buttons["Start"].appears(), "Discard left the workout running")
    }
}

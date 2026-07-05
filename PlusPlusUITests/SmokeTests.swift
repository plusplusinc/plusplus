import XCTest

/// End-to-end smoke tests for the core flows, run on the CI simulator.
/// Screenshots are attached at key points and exported as workflow
/// artifacts, standing in for hands-on validation between Mac sessions.
/// The app launches with --uitest-reset (in-memory store, seed data only).
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitest-reset"]
        app.launch()
    }

    // MARK: - Flows

    func testBuildWorkoutWithExerciseAndWeight() throws {
        createWorkout(named: "Push Day")
        addExercise(searching: "Bench Press")

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))

        // First tap on the weight stepper lands on the 45 lb default.
        let weightStepper = app.steppers["Weight"]
        XCTAssertTrue(weightStepper.waitForExistence(timeout: 5))
        weightStepper.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 5))
        weightStepper.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))

        snap("workout-detail")
    }

    func testCreateCustomExerciseWithNotes() throws {
        createWorkout(named: "PT")

        app.buttons["addExerciseButton"].tap()
        let newButton = app.buttons["newExerciseButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.tap()

        let nameField = app.textFields["exerciseNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Band Pulses")

        snap("exercise-editor")

        app.buttons["saveExerciseButton"].tap()

        // Back in the picker: the custom exercise is in the list; add it.
        search(for: "Band Pulses")
        let row = app.cells.staticTexts["Band Pulses"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.staticTexts["Band Pulses"].waitForExistence(timeout: 5))
        snap("custom-exercise-in-workout")
    }

    func testExecuteWorkoutAndSeeHistory() throws {
        createWorkout(named: "Quick Session")
        addExercise(searching: "Push-Up")

        app.buttons["startWorkoutButton"].tap()

        // 3 sets (default): complete each, skipping the rest countdown.
        for setIndex in 1...3 {
            let complete = app.buttons["completeSetButton"]
            XCTAssertTrue(complete.waitForExistence(timeout: 10), "Set \(setIndex) screen should appear")
            if setIndex == 1 {
                snap("set-logging")
            }
            complete.tap()

            if setIndex < 3 {
                skipRest(afterSet: setIndex)
            }
        }

        XCTAssertTrue(app.staticTexts["Workout Complete"].waitForExistence(timeout: 5))
        snap("workout-complete")
        app.buttons["sessionDoneButton"].tap()

        // Back out to the list, then into history.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()

        let history = app.buttons["historyButton"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()

        XCTAssertTrue(app.staticTexts["Quick Session"].waitForExistence(timeout: 5))
        app.staticTexts["Quick Session"].tap()
        XCTAssertTrue(app.staticTexts["Set 1"].waitForExistence(timeout: 5))
        snap("history-detail")
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func createWorkout(named name: String) {
        let fab = app.buttons["newWorkoutButton"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let alert = app.alerts["New Workout"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(name)
        alert.buttons["Create"].tap()

        // Lands on the new workout's detail screen.
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    private func search(for text: String) {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(text)
    }

    private func addExercise(searching name: String) {
        app.buttons["addExerciseButton"].tap()
        search(for: name)
        let row = app.cells.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    /// Skips the rest countdown, retrying once if the tap landed during a
    /// view transition (a tap synthesized mid-transition can be dropped).
    private func skipRest(afterSet setIndex: Int) {
        let skip = app.buttons["skipRestButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "Rest screen should appear after set \(setIndex)")
        if setIndex == 1 {
            snap("rest-countdown")
        }
        skip.tap()

        let complete = app.buttons["completeSetButton"]
        if !complete.waitForExistence(timeout: 5) && skip.exists {
            skip.tap()
        }
        XCTAssertTrue(complete.waitForExistence(timeout: 10), "Set \(setIndex + 1) screen should appear after skipping rest")
    }
}

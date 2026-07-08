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

    func testBuildRoutineWithExerciseAndWeight() throws {
        createRoutine(named: "Push Day")
        addExercise(searching: "Bench Press")

        // The exercise appears as a rail row; tapping it opens the
        // planning sheet where metrics are edited (v2 design).
        let row = app.staticTexts["Bench Press"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // First increment lands on the 45 lb default. The value renders
        // as a tappable button (it opens the wheel picker), so assert on
        // the button's label — there is no separate static text.
        let increment = app.buttons["weightIncrement"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        let weightValue = app.buttons["weightValue"]
        increment.tap()
        XCTAssertTrue(waitForLabel(weightValue, "45 lb"), "first increment lands on the empty-bar default")
        increment.tap()
        XCTAssertTrue(waitForLabel(weightValue, "50 lb"), "second increment steps by 5 lb")

        snap("exercise-sheet")

        app.buttons["closeExerciseSheet"].tap()
        XCTAssertTrue(app.buttons["startWorkoutButton"].waitForExistence(timeout: 5))
        snap("routine-detail")
    }

    func testCreateCustomExerciseWithNotes() throws {
        // Not "PT": typeText with two consecutive shifted characters is a
        // known flake on slow simulators (the second shift can drop).
        createRoutine(named: "Rehab")

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
        snap("custom-exercise-in-routine")
    }

    func testExecuteWorkoutAndSeeHistory() throws {
        createRoutine(named: "Quick Session")
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
        snap("routine-complete")
        app.buttons["sessionDoneButton"].tap()

        // Back out to the list, then into the record via the Today tab
        // (the standalone History screen died with #109).
        let back = app.buttons["backButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()

        let today = app.tabBars.buttons["today"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()

        // Snapshot the list before asserting, so a failure here leaves
        // visual evidence of what history actually showed.
        snap("history-list")

        // Generous timeouts: on a loaded CI simulator, the first snapshot
        // after navigation can take most of a minute to evaluate.
        XCTAssertTrue(app.staticTexts["Quick Session"].waitForExistence(timeout: 30))
        app.staticTexts["Quick Session"].tap()
        XCTAssertTrue(app.staticTexts["Set 1"].waitForExistence(timeout: 15))
        snap("history-detail")
    }

    /// Regression for the third-strike scroll bug: with enough exercises
    /// to overflow the screen, the detail list must actually scroll (the
    /// long-press rail gestures used to starve the scroll pan).
    func testDetailListScrollsWhenOverflowing() throws {
        app.terminate()
        app.launchArguments += ["--uitest-bigworkout"]
        app.launch()

        let routinesTab = app.tabBars.buttons["routines"]
        XCTAssertTrue(routinesTab.waitForExistence(timeout: 10))
        routinesTab.tap()

        let card = app.staticTexts["Big Day"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let addRow = app.buttons["addExerciseButton"]
        XCTAssertTrue(addRow.waitForExistence(timeout: 5), "add row is in the hierarchy even while offscreen")
        XCTAssertFalse(addRow.isHittable, "16 rows must overflow — otherwise this test can't prove scrolling")
        snap("overflow-top")

        // Swipe on the rows themselves, where a thumb naturally lands.
        for _ in 0..<4 where !addRow.isHittable {
            app.swipeUp()
        }

        snap("overflow-after-scroll")
        XCTAssertTrue(addRow.isHittable, "the add-exercise row at the bottom of the rail must be reachable by scrolling")
    }

    /// The setup-as-timeline onboarding: a fresh install's Today shows
    /// three gated setup entries; completing them bottom-up commits each
    /// to the rail and stages the first real routine.
    func testSetupTimelineOnboarding() throws {
        app.terminate()
        app.launchArguments += ["--uitest-onboarding"]
        app.launch()

        // Fresh install: equipment is the only ready step; the ones
        // above it are gated.
        let equipCTA = app.buttons["setupEquipmentStep"]
        XCTAssertTrue(equipCTA.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Needs your equipment first"].exists)
        snap("setup-fresh")
        equipCTA.tap()

        // Step 1: the real catalog in setup mode (v4 SSF) — pick
        // everything via the Commercial gym preset, confirm on the bar.
        let setEquipment = app.buttons["setEquipmentButton"]
        XCTAssertTrue(setEquipment.waitForExistence(timeout: 5))
        app.staticTexts["Commercial gym"].tap()
        setEquipment.tap()
        // The optional populate offer (#185): take it, so the picker
        // and library flows downstream have content.
        let populate = app.buttons["Add them"]
        XCTAssertTrue(populate.waitForExistence(timeout: 5))
        populate.tap()

        // Step 2 unlocks: seed the starter split.
        let routineCTA = app.buttons["setupRoutineStep"]
        XCTAssertTrue(routineCTA.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Equipment set"].waitForExistence(timeout: 5))
        snap("setup-step2")
        routineCTA.tap()
        let split = app.buttons["starterSplitButton"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        split.tap()

        // Step 3 unlocks: schedule Push Day for today so it stages.
        let scheduleCTA = app.buttons["setupScheduleStep"]
        XCTAssertTrue(scheduleCTA.waitForExistence(timeout: 10))
        snap("setup-step3")
        scheduleCTA.tap()

        let daysTab = app.buttons["Days"]
        XCTAssertTrue(daysTab.waitForExistence(timeout: 5))
        daysTab.tap()
        let weekday = Calendar.current.component(.weekday, from: Date())
        let dayChip = app.buttons["scheduleDay\(weekday)"]
        XCTAssertTrue(dayChip.waitForExistence(timeout: 5))
        dayChip.tap()
        // Routine settings is a pushed page now (v4 SSA) — back, not Done.
        app.buttons["backButton"].tap()

        // Scaffold fully committed; the real thing appears above it —
        // Push Day staged and startable.
        XCTAssertTrue(app.staticTexts["Schedule set"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["startStagedButton"].waitForExistence(timeout: 10))
        snap("setup-complete")
    }

    // MARK: - Helpers

    /// Waits for an element's label to become `label` — for values that
    /// render inside buttons, where waitForExistence can't see the text.
    /// The timeout must absorb accessibility-snapshot latency: on a loaded
    /// CI simulator a single evaluation has been observed to take ~15 s.
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 30) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func createRoutine(named name: String) {
        // v3 nav (#109): the app lands on Today; routine creation is the
        // contextual + in the Routines tab header.
        let routinesTab = app.tabBars.buttons["routines"]
        XCTAssertTrue(routinesTab.waitForExistence(timeout: 10))
        routinesTab.tap()

        let plus = app.buttons["newRoutineButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()

        let alert = app.alerts["New Routine"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(name)
        alert.buttons["Create"].tap()

        // Lands on the new routine's detail screen (custom header — v2
        // has no system navigation bar here).
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addExerciseButton"].waitForExistence(timeout: 5))
    }

    private func search(for text: String) {
        let searchField = app.textFields["searchField"].firstMatch
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

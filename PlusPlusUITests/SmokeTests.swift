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

    /// The Routines-tab catalog path specifically: template detail must
    /// open from THIS stack, not just Today's setup step. Build 33
    /// shipped with the RoutineTemplate destination registered inside
    /// the pushed catalog screen — Today's path resolved it, the
    /// Routines tab hit SwiftUI's missing-destination placeholder.
    func testRoutinesTabOpensTemplateDetail() throws {
        let routinesTab = app.tabBars.buttons["Routines"]
        XCTAssertTrue(routinesTab.waitForExistence(timeout: 10))
        routinesTab.tap()

        let plus = app.buttons["newRoutineButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()

        // Search pins the template (lazy-List rule). Under plain
        // --uitest-reset all built-in gear is owned (populateLibrary),
        // so the default My-equipment filter hides nothing here; a
        // bodyweight template ADDITIONALLY survives zero-owned stores
        // (the --uitest-onboarding world) — don't swap in a
        // gear-requiring template and trust this test to cover both.
        let searchToggle = app.buttons["routineCatalogSearchFieldToggle"]
        XCTAssertTrue(searchToggle.waitForExistence(timeout: 5))
        searchToggle.tap()
        let field = app.textFields["routineCatalogSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Bodyweight Basics")
        let templateRow = app.staticTexts["Bodyweight Basics"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 5))
        templateRow.tap()

        // The detail screen, not the triangle: Add is its primary action.
        XCTAssertTrue(app.buttons["addTemplateButton"].waitForExistence(timeout: 5))
        snap("routines-tab-template-detail")
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

        let today = app.tabBars.buttons["Today"]
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

        let routinesTab = app.tabBars.buttons["Routines"]
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

        // Step 1: the real catalog in setup mode (v4 SSF) — the preset
        // strip died (#203). A fresh store owns NOTHING (#232) —
        // ownership is opt-in, so pick the way users do: toggle ON gear
        // you have. First-screen rows only (lazy List rows below the
        // fold aren't realized) — use the two alphabetically-FIRST
        // catalog names so catalog growth can't push them under the
        // fold again (#222 moved Battle Ropes to row 11 and broke this).
        let setEquipment = app.buttons["setEquipmentButton"]
        XCTAssertTrue(setEquipment.waitForExistence(timeout: 5))
        for name in ["Ab Crunch Machine", "Ab Wheel"] {
            let row = app.switches["toggle-\(name)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "missing equipment toggle for \(name)")
            XCTAssertEqual(row.value as? String, "0", "\(name) should start un-owned on a fresh store")
            row.switches.firstMatch.tap()
            XCTAssertEqual(row.value as? String, "1", "tapping \(name) should own it")
        }
        setEquipment.tap()
        // The optional populate offer now asks from Today (#204): take
        // it, so the picker and library flows downstream have content.
        let populate = app.alerts.buttons["Add them"]
        XCTAssertTrue(populate.waitForExistence(timeout: 10))
        populate.tap()

        // Step 2 unlocks: pick a routine from the catalog (#246 — the
        // two-option seeder sheet died; the catalog is THE creation
        // surface, and this exercises its search + Add end to end).
        let routineCTA = app.buttons["setupRoutineStep"]
        XCTAssertTrue(routineCTA.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Equipment set"].waitForExistence(timeout: 5))
        snap("setup-step2")
        routineCTA.tap()

        // Search pins the template regardless of sort order or catalog
        // growth (the lazy-List rule: only realized rows exist).
        let searchToggle = app.buttons["routineCatalogSearchFieldToggle"]
        XCTAssertTrue(searchToggle.waitForExistence(timeout: 5))
        searchToggle.tap()
        let field = app.textFields["routineCatalogSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Bodyweight Basics")
        let templateRow = app.staticTexts["Bodyweight Basics"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 5))
        templateRow.tap()
        let add = app.buttons["addTemplateButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        snap("setup-step2-added")

        // Add lands in the new routine; pop back to Today for step 3.
        for _ in 0..<4 where !app.buttons["setupScheduleStep"].exists {
            let back = app.buttons["backButton"]
            guard back.waitForExistence(timeout: 5) else { break }
            back.tap()
        }

        // Step 3 unlocks: schedule Bodyweight Basics for today so it stages.
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
        // Bodyweight Basics staged and startable.
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
        // v3 nav (#109): the app lands on Today; the Routines header +
        // pushes the routine catalog (#223), whose first row creates a
        // blank routine.
        let routinesTab = app.tabBars.buttons["Routines"]
        XCTAssertTrue(routinesTab.waitForExistence(timeout: 10))
        routinesTab.tap()

        let plus = app.buttons["newRoutineButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()

        let createRow = app.buttons["createBlankRoutine"]
        XCTAssertTrue(createRow.waitForExistence(timeout: 5))
        createRow.tap()

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

import XCTest

/// A workout at the largest text size, run first within `testWorkoutAndFiltersAtLargestTextSize`:
/// its bar and End's dialog under the audit, and where Start and a relaunch land. Here the
/// equipment under the title stands taller than the screen, so the current exercise starts out
/// below it, and Start's scroll to the top runs far.
@MainActor
extension TitleWrappingUITests {
    /// Launches at this size into a workout of two rows joined, with four more for their
    /// equipment, seeded, since adding is the later checks', and pushes it from the Workouts
    /// screen: Start and a relaunch land on the current exercise, and a workout's bar, paused,
    /// and End's dialog pass the audit. Running, the bar differs only in its key's shorter
    /// Pause. Leaves the workout showing, the workout session discarded.
    func liveWorkoutAtAX5(in app: XCUIApplication) throws {
        try XCTContext
            .runActivity(named: "A workout at AX5 lands, and its bar passes the audit") { _ in
                app.launchSeeding(
                    [
                        "dumbbell-bench-press", "kneeling-hip-flexor-stretch", "pull-up",
                        "goblet-squat", "band-pull-apart", "balance-board-hold",
                    ],
                    textSize: Self.largestTextSize,
                    arguments: ["-seedSuperset", "0,1"],
                )
                // Pushed from the Workouts screen, with a back chevron in the bar for ++; the
                // drawer and Workouts are audited on the way, not on a trip of their own.
                try drawerAtAX5(in: app)
                app.workoutRows.firstMatch.tap()
                XCTAssertTrue(app.buttons["Start"].appears(), "The workout opened no Start")
                app.buttons["Start"].tap()
                let time = app.workoutTime
                XCTAssertTrue(time.appears(within: 3), "Start began no workout")
                assertLandedOnTheCurrentExercise(in: app, after: "Start")
                attach(named: "workout-ax5")
                app.relaunch()
                XCTAssertTrue(time.appears(), "The workout did not come back")
                assertLandedOnTheCurrentExercise(in: app, after: "the relaunch")
                attach(named: "workout-relaunched-ax5")
                time.tap()
                XCTAssertEqual(reading(time.label, becoming: "Resume", within: 2), "Resume")
                try auditBelowTheBar(in: app)
                app.openEndDialog()
                attach(named: "end-dialog-ax5")
                try auditBelowTheBar(
                    in: app,
                    systemTexts: ["End this workout?", "Nothing has been logged yet."],
                )
                // Discarded from the dialog already open.
                app.buttons["Discard workout"].tap()
                XCTAssertTrue(app.buttons["Start"].appears(), "Discard left the workout running")
            }
    }

    /// The drawer, its places kept whole, and the Workouts screen pass the audit at this size,
    /// opened with ++ over the workout the launch seeded. Ends on Workouts.
    private func drawerAtAX5(in app: XCUIApplication) throws {
        try XCTContext.runActivity(named: "The drawer and the Workouts screen at AX5") { _ in
            try app.openDrawer(andTap: "Workouts") {
                attach(named: "drawer-ax5")
                try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            }
            let row = app.workoutRows.firstMatch
            XCTAssertTrue(row.appears(), "The workout isn't listed")
            attach(named: "workouts-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            try workoutsFiltersAtAX5(in: app)
        }
    }

    /// The Workouts list with a filter on and Clear leading its buttons, and the Length sheet,
    /// its presets stacked and its wheels, pass the audit; the Length sheet, opened at half
    /// height, offers the full height its content overflows into. Leaves no filter on.
    private func workoutsFiltersAtAX5(in app: XCUIApplication) throws {
        app.buttons["Muscle"].tap()
        let chest = app.scrollViews.buttons["Chest"]
        XCTAssertTrue(chest.appears(), "Muscle opened no sheet of chips")
        chest.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(chest.disappears(), "Done left the chips up")
        let clear = app.buttons["Clear filters"]
        XCTAssertTrue(clear.exists, "No Clear with the filter on")
        attach(named: "workouts-filtered-ax5")
        try auditBelowTheBar(in: app)
        // At this size Length is past the screen's edge, as the bar scrolls sideways.
        let length = app.buttons["Length"]
        app.buttons["Equipment"].swipeLeft()
        XCTAssertTrue(reading(length.isHittable, becoming: true, within: 2), "Length never in view")
        length.tap()
        let upTo20 = app.buttons["20 minutes or less"]
        XCTAssertTrue(upTo20.appears(), "Length opened no presets")
        // Its presets and wheels overflow half height at this size, so the sheet offers its
        // large height, which only the system's grabber shows.
        let grabber = app.buttons["Sheet Grabber"]
        grabber.tap()
        XCTAssertEqual(grabber.value(becoming: "Expanded"), "Expanded", "No full-height Length")
        attach(named: "length-sheet-ax5")
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
        app.buttons["Done"].tap()
        XCTAssertTrue(upTo20.disappears(), "Done left the Length sheet up")
        clear.tap()
        XCTAssertTrue(clear.disappears(), "Clear left a filter on")
    }

    /// The current exercise's row just under the bar, the key not going back to it.
    private func assertLandedOnTheCurrentExercise(in app: XCUIApplication, after step: String) {
        let current = app.exerciseRows.firstMatch
        let bar = app.navigationBars.firstMatch.frame.maxY
        // Its label sits a spacing step and the row's inset under the bar.
        let isLanded = { (top: CGFloat) in top >= bar - 1 && top < bar + 60 }
        let top = reading(current.frame.minY, until: isLanded, within: 3)
        XCTAssertTrue(
            isLanded(top),
            "After \(step), the current exercise's top is at \(top), the bar's bottom at \(bar)",
        )
        // Through "Start in" there is no key, unless it goes back.
        let key = app.workoutKey
        XCTAssertFalse(
            key.exists && key.label.hasPrefix("Go to current exercise"),
            "The key goes back after \(step)",
        )
    }
}

import XCTest

/// A workout at the largest text size, run within `testWrappedTitleAtLargestTextSize`: its bar
/// and End's dialog under the audit, and where Start and a relaunch land. Here the equipment
/// under the title stands taller than the screen, so the current exercise starts out below it,
/// and Start's scroll to the top runs far.
@MainActor
extension TitleWrappingUITests {
    /// On a routine like the one the checks before made, its two rows joined, with four more
    /// for their equipment, seeded at a launch of its own, since adding is checked above and
    /// four adds cost more than a launch: Start and a relaunch land on the current exercise, and
    /// a workout's bar, paused, and End's dialog pass the audit. Running, the bar differs only
    /// in its key's shorter Pause.
    func workoutAtAX5(in app: XCUIApplication) throws {
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
                XCTAssertTrue(app.buttons["Start"].appears(), "The routine opened no Start")
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
        XCTAssertFalse(
            app.workoutKey.label.hasPrefix("Go to current exercise"),
            "The key goes back after \(step)",
        )
    }
}

import XCTest

/// A workout at the largest text size, run within `testWrappedTitleAtLargestTextSize`: its bar
/// and Finish's menu under the audit, and where Start and a relaunch land. Here the equipment
/// under the title stands taller than the screen, so the current exercise starts out below it,
/// and Start's scroll to the top runs far.
extension TitleWrappingUITests {
    /// From the Routines screen the drawer left, with exercises added for their equipment: Start
    /// and a relaunch land on the current exercise, and a workout's bar, running and paused, and
    /// Finish's menu pass the audit.
    @MainActor
    func workoutAtAX5(in app: XCUIApplication) throws {
        try XCTContext
            .runActivity(named: "A workout at AX5 lands, and its bar passes the audit") { _ in
                app.buttons.matching(identifier: "routines.row").firstMatch.tap()
                XCTAssertTrue(app.buttons["Start"].appears(), "The routine opened no Start")
                app.addExercise("Pull-up, Pull-up bar", searching: "pull-up")
                app.addExercise("Goblet squat, Kettlebell", searching: "goblet")
                app.addExercise("Band pull-apart, Band", searching: "pull-apart")
                app.addExercise("Balance board hold, Balance board", searching: "balance")
                app.buttons["Start"].tap()
                let time = app.workoutTime
                XCTAssertTrue(time.appears(within: 3), "Start began no workout")
                assertLandedOnTheCurrentExercise(in: app, after: "Start")
                attach(named: "workout-ax5")
                try auditBelowTheBar(in: app)
                app.relaunch()
                XCTAssertTrue(time.appears(), "The workout did not come back")
                assertLandedOnTheCurrentExercise(in: app, after: "the relaunch")
                attach(named: "workout-relaunched-ax5")
                time.tap()
                XCTAssertEqual(reading(time.label, becoming: "Resume", within: 2), "Resume")
                try auditBelowTheBar(in: app)
                XCTAssertNotNil(app.openFinishMenu(), "No Finish in the menu")
                attach(named: "finish-menu-ax5")
                try auditBelowTheBar(in: app)
                // Discarded from the menu already open.
                app.buttons["Discard workout"].tap()
                XCTAssertTrue(app.buttons["Start"].appears(), "Discard left the workout running")
            }
    }

    /// The current exercise's row just under the bar, with no way back to it showing.
    @MainActor
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
        XCTAssertFalse(app.buttons["workout.current"].exists, "The way back shows after \(step)")
    }
}

import XCTest

/// A relaunch into a workout at the largest text size, where the equipment under the title
/// stands taller than the screen and the current exercise starts out below it. The scroll to the
/// top at Start runs far there, and its spring was still settling as the grow began. Its own
/// test, not part of `TitleWrappingUITests`, the other AX5 launch, which runs close to XCTest's
/// three minutes on Xcode Cloud already.
extension WorkoutUITests {
    @MainActor
    func testRelaunchLandsOnTheCurrentExerciseAtAX5() {
        let app = XCUIApplication()
        _ = app.launchNewRoutine(
            textSize: "UICTContentSizeCategoryAccessibilityXXXL",
            arguments: ["-fallbackNames", "YES"],
        )
        app.addExercise("Barbell bench press, Barbell, bench", searching: "bench press")
        app.addExercise("Pull-up, Pull-up bar", searching: "pull-up")
        app.addExercise("Goblet squat, Kettlebell", searching: "goblet")
        app.addExercise("Band pull-apart, Band", searching: "pull-apart")
        app.addExercise("Balance board hold, Balance board", searching: "balance")
        app.addExercise("Biceps curl, Dumbbells", searching: "biceps")
        app.buttons["Start"].tap()
        XCTAssertTrue(app.workoutTime.appears(within: 3), "Start began no workout")
        assertLandedOnTheCurrentExercise(in: app, "Start")
        app.relaunch()
        XCTAssertTrue(app.workoutTime.appears(), "The workout did not come back")
        assertLandedOnTheCurrentExercise(in: app, "the relaunch")
        attach(named: "workout-relaunched-ax5")
        app.discardWorkout()
    }

    /// The current exercise's row just under the bar, with no way back to it showing.
    @MainActor
    private func assertLandedOnTheCurrentExercise(in app: XCUIApplication, _ after: String) {
        let current = app.exerciseRows.firstMatch
        let bar = app.navigationBars.firstMatch.frame.maxY
        // Its label sits a spacing step and the row's inset under the bar.
        let landed = reading(
            current.frame.minY,
            until: { $0 >= bar - 1 && $0 < bar + 60 },
            within: 3,
        )
        XCTAssertTrue(
            landed >= bar - 1 && landed < bar + 60,
            "After \(after), the current exercise's top is at \(landed), the bar's bottom \(bar)",
        )
        XCTAssertFalse(app.buttons["workout.current"].exists, "The way back shows after \(after)")
    }
}

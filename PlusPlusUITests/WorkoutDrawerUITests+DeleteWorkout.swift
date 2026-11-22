import XCTest

@MainActor
extension WorkoutDrawerUITests {
    /// On a new workout with nothing saved, the ••• menu's Delete is dimmed. That such a workout
    /// can't be deleted is `AppSessionDeleteTests`'; this is the menu item's wire to it,
    /// which only the running app's bar menu shows. Leaves the menu closed.
    func newWorkoutDimsDelete(in app: XCUIApplication) {
        let more = app.buttons["workout.more"]
        XCTAssertTrue(more.settles(), "••• kept moving")
        more.tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.appears(), "••• opened no menu with Delete")
        XCTAssertFalse(delete.isEnabled, "Delete isn't dimmed on a workout with nothing saved")
        // A tap away from the menu closes it, and the bar takes taps again once it has closed.
        // In the bar, between the chevron and the menu: the empty workout below opens Add
        // exercise on a tap.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.1)).tap()
        XCTAssertTrue(delete.disappears(), "The menu stayed open")
        XCTAssertTrue(
            reading(app.buttons["BackButton"].isHittable, becoming: true, within: 2),
            "The bar stayed covered after the menu closed",
        )
    }

    /// On the Workouts screen with two workouts, a row's hold menu and its swipe each ask before
    /// deleting, and the pushed workout's ••• deletes it and shows Workouts. The system's swipe
    /// actions, context menu, and alert, and a bar menu, show only in the running app; what a
    /// delete stores and what shows next is `AppSessionDeleteTests`', and that a deleted
    /// workout stays gone after a relaunch `StoreDeleteTests`'.
    func workoutsDeleteWorkouts(in app: XCUIApplication, title: XCUIElement) {
        let delete = app.buttons["Delete"]
        let listed = ["Chest day", "Back"]
        XCTContext.runActivity(named: "A row's hold menu asks first, and Cancel keeps it") { _ in
            let row = app.listedWorkout(named: "Back")
            XCTAssertTrue(row.settles(), "The row kept moving")
            row.press(forDuration: XCUICoordinate.contextMenuHold)
            XCTAssertTrue(delete.appears(), "Holding a row opened no menu with Delete")
            attach(named: "workout-held")
            delete.tap()
            app.answerAlert("Delete Back?", with: "Cancel")
            XCTAssertEqual(app.workoutRowLabels, listed, "Cancel changed the list")
        }
        XCTContext.runActivity(named: "A row's swipe asks first, and Delete takes it out") { _ in
            app.listedWorkout(named: "Back").swipeOpen()
            XCTAssertTrue(delete.appears(), "A swipe did not open the row")
            attach(named: "workout-swiped")
            delete.tap()
            app.answerAlert("Delete Back?", with: "Delete")
            let left = ["Chest day"]
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: left, within: 2), left)
        }
        XCTContext.runActivity(named: "A pushed workout's ••• deletes it and shows Workouts") { _ in
            app.listedWorkout(named: "Chest day").tap()
            XCTAssertEqual(
                title.value(becoming: "Chest day"),
                "Chest day",
                "The row pushed no workout",
            )
            let more = app.buttons["workout.more"]
            XCTAssertTrue(more.settles(), "••• kept moving")
            XCTAssertEqual(more.label, "More", "VoiceOver doesn't read ••• as More")
            more.tap()
            XCTAssertTrue(delete.appears(), "••• opened no menu with Delete")
            delete.tap()
            app.answerAlert("Delete Chest day?", with: "Delete")
            XCTAssertTrue(title.disappears(), "Deleting the workout left it showing")
            XCTAssertTrue(app.buttons["Menu"].appears(), "Workouts did not show")
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: [], within: 2), [])
        }
    }
}

import XCTest

@MainActor
extension RoutineDrawerUITests {
    /// On a new routine with nothing saved, the ••• menu's Delete is dimmed. That such a routine
    /// can't be deleted is `AppSessionDeleteTests`'; this is the menu item's wire to it,
    /// which only the running app's bar menu shows. Leaves the menu closed.
    func newRoutineDimsDelete(in app: XCUIApplication) {
        let more = app.buttons["workout.more"]
        XCTAssertTrue(more.settles(), "••• kept moving")
        more.tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.appears(), "••• opened no menu with Delete")
        XCTAssertFalse(delete.isEnabled, "Delete isn't dimmed on a routine with nothing saved")
        // A tap away from the menu closes it, and the bar takes taps again once it has closed.
        // In the bar, between the chevron and the menu: the empty routine below opens Add
        // exercise on a tap.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.1)).tap()
        XCTAssertTrue(delete.disappears(), "The menu stayed open")
        XCTAssertTrue(
            reading(app.buttons["BackButton"].isHittable, becoming: true, within: 2),
            "The bar stayed covered after the menu closed",
        )
    }

    /// On the Routines screen with two routines, a row's hold menu and its swipe each ask before
    /// deleting, and the pushed routine's ••• deletes it and shows Routines. The system's swipe
    /// actions, context menu, and alert, and a bar menu, show only in the running app; what a
    /// delete stores and what shows next is `AppSessionDeleteTests`', and that a deleted
    /// routine stays gone after a relaunch `StoreDeleteTests`'.
    func routinesDeleteRoutines(in app: XCUIApplication, title: XCUIElement) {
        let delete = app.buttons["Delete"]
        let listed = ["Chest day", "Back"]
        XCTContext.runActivity(named: "A row's hold menu asks first, and Cancel keeps it") { _ in
            let row = app.routineRow(named: "Back")
            XCTAssertTrue(row.settles(), "The row kept moving")
            row.press(forDuration: 1)
            XCTAssertTrue(delete.appears(), "Holding a row opened no menu with Delete")
            attach(named: "routine-held")
            delete.tap()
            app.answerAlert("Delete Back?", with: "Cancel")
            XCTAssertEqual(app.routineRowLabels, listed, "Cancel changed the list")
        }
        XCTContext.runActivity(named: "A row's swipe asks first, and Delete takes it out") { _ in
            app.routineRow(named: "Back").swipeOpen()
            XCTAssertTrue(delete.appears(), "A swipe did not open the row")
            attach(named: "routine-swiped")
            delete.tap()
            app.answerAlert("Delete Back?", with: "Delete")
            let left = ["Chest day"]
            XCTAssertEqual(reading(app.routineRowLabels, becoming: left, within: 2), left)
        }
        XCTContext.runActivity(named: "A pushed routine's ••• deletes it and shows Routines") { _ in
            app.routineRow(named: "Chest day").tap()
            XCTAssertEqual(
                title.value(becoming: "Chest day"),
                "Chest day",
                "The row pushed no routine",
            )
            let more = app.buttons["workout.more"]
            XCTAssertTrue(more.settles(), "••• kept moving")
            XCTAssertEqual(more.label, "More", "VoiceOver doesn't read ••• as More")
            more.tap()
            XCTAssertTrue(delete.appears(), "••• opened no menu with Delete")
            delete.tap()
            app.answerAlert("Delete Chest day?", with: "Delete")
            XCTAssertTrue(title.disappears(), "Deleting the routine left it showing")
            XCTAssertTrue(app.buttons["Menu"].appears(), "Routines did not show")
            XCTAssertEqual(reading(app.routineRowLabels, becoming: [], within: 2), [])
        }
    }
}

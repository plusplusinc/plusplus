import XCTest

@MainActor
extension RoutineDrawerUITests {
    /// On the Routines screen with two routines, a row's hold menu and its swipe each ask before
    /// deleting, and the pushed routine's ••• deletes it and shows Routines. The system's swipe
    /// actions, context menu, and alert, and a bar menu, show only in the running app; what a
    /// delete stores and what shows next is `RoutineSessionDeleteTests`', and that a deleted
    /// routine stays gone after a relaunch `RoutineStoreDeleteTests`'.
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
            let more = app.buttons["routine.more"]
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

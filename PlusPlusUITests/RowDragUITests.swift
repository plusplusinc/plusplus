import XCTest

/// Dragging, joining, and deleting rows with real touches over the scroll view, on nine seeded
/// rows that run past one screen. Where a drag lands, what a node's span makes, and which
/// neighbor a rest pairs with are unit-tested in the package; this checks each gesture once,
/// that it reaches that arithmetic. A class of its own, so that with parallel testing no class
/// holds two long tests.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class RowDragUITests: XCTestCase {
    /// Reordering, supersets, and deleting, on the nine rows `testRenameAtDefaultSize` adds,
    /// seeded.
    @MainActor
    func testDragAndDeleteRows() {
        let app = XCUIApplication()
        app.launchSeedingNineExercises(named: "Arm and back day")
        reorderExercises(in: app)
        supersetExercises(in: app)
        deleteExercises(in: app)
    }
}

extension RowDragUITests {
    /// The system's swipe actions: a swipe opens a row's Delete, a tap elsewhere closes it, and
    /// a full swipe deletes outright. What a delete does to a superset is
    /// `RoutineSupersetTests`', and Start going with the last row `RoutineAutosaveUITests`'.
    @MainActor
    func deleteExercises(in app: XCUIApplication) {
        let delete = app.buttons["Delete"]
        XCTContext.runActivity(named: "A swipe opens a row, and Delete deletes it") { _ in
            app.exerciseRows.element(boundBy: 1).swipeOpen()
            XCTAssertTrue(delete.appears(), "A swipe did not open the row")
            attach(named: "row-open")
            delete.tap()
            XCTAssertEqual(app.exerciseCount(becoming: 8), 8)
            XCTAssertTrue(delete.disappears())
        }
        XCTContext.runActivity(named: "A tap anywhere else closes an open row") { _ in
            let open = {
                app.exerciseRows.element(boundBy: 0).swipeOpen()
                XCTAssertTrue(delete.appears(), "A swipe did not open the row")
            }
            open()
            // The empty end of the capsules' second line, under the title: the list runs on
            // under Start, so there may be no gap between Add exercise and Start.
            app.equipment.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.8)).tap()
            XCTAssertTrue(delete.disappears(), "A tap on empty screen left the row open")
            open()
            // The tap closes the row and still starts a workout, which is discarded.
            app.buttons["Start"].tap()
            XCTAssertTrue(delete.disappears(), "A tap on Start left the row open")
            app.discardWorkout()
            open()
            // The tap closes the row and still opens the picker.
            _ = app.openPicker()
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(app.searchFields.firstMatch.disappears())
            XCTAssertFalse(delete.exists, "Add exercise left the row open")
            let count = app.exerciseCount(becoming: 7, within: 1)
            XCTAssertEqual(count, 8, "A tap outside the row deleted it")
        }
        XCTContext.runActivity(named: "A full swipe deletes") { _ in
            app.lastExerciseRow.fullSwipeLeft()
            XCTAssertEqual(app.exerciseCount(becoming: 7), 7, "A full swipe did not delete")
        }
    }
}

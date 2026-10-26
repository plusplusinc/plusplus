import XCTest

/// Dragging, joining, and deleting rows with real touches over the scroll view, on nine seeded
/// rows that run past one screen. Where a drag lands, what a node's span makes, and which
/// neighbor a rest pairs with are unit-tested in the package; this checks each gesture once,
/// that it reaches that arithmetic.
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
    /// The system's swipe actions: a swipe opens a row's Delete, a tap on Start closes it, and
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
        // A tap inside the list closing the row is the system's swipe-actions container; Start's
        // bar is the app's own.
        XCTContext.runActivity(named: "A tap on Start closes an open row") { _ in
            app.exerciseRows.element(boundBy: 0).swipeOpen()
            XCTAssertTrue(delete.appears(), "A swipe did not open the row")
            // The tap closes the row and still starts a workout, which is discarded.
            app.buttons["Start"].tap()
            XCTAssertTrue(delete.disappears(), "A tap on Start left the row open")
            app.discardWorkout()
            XCTAssertEqual(app.exerciseCount(becoming: 7, within: 1), 8, "Start deleted the row")
        }
        XCTContext.runActivity(named: "A full swipe deletes") { _ in
            app.lastExerciseRow.fullSwipeLeft()
            XCTAssertEqual(app.exerciseCount(becoming: 7), 7, "A full swipe did not delete")
        }
    }
}

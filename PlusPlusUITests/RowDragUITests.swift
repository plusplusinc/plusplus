import XCTest

/// Dragging, joining, and deleting rows with real touches over the scroll view, on nine seeded
/// rows that run past one screen, and then Create's add on that long a routine. Where a drag
/// lands, what a node's span makes, and which neighbor a rest pairs with are unit-tested in the
/// package; this checks each gesture once, that it reaches that arithmetic.
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
        createOnALongRoutine(in: app)
        createdHoldMenuDeletes(in: app)
    }

    /// From the top of a routine longer than the screen, Create scrolls the list to its end and
    /// the row lands there in view, clear of Add exercise's +, before its own sheet opens on
    /// Customize; a swipe down closes the sheet and keeps the row. The empty routine's is
    /// `RoutineAutosaveUITests`'.
    @MainActor
    private func createOnALongRoutine(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Create on a long routine lands in view") { _ in
            let count = app.exerciseRows.count
            app.exerciseRows.firstMatch.swipeDown()
            let search = app.openPicker()
            app.search(for: "zq")
            app.buttons["picker.create"].tap()
            XCTAssertTrue(search.disappears(), "Create left Add exercise up")
            XCTAssertEqual(app.exerciseCount(becoming: count + 1), count + 1, "Create added no row")
            // Landed at the list's end, clear of the +, before its sheet covers it.
            XCTAssertEqual(app.exerciseRowLabels.last, "Zq, 3 sets of 10 reps")
            XCTAssertTrue(app.lastRowClearsAddExercise(), "The created row landed out of view")
            let name = app.textFields["customize.name"]
            XCTAssertTrue(app.createdSheetOpens(), "The created row's sheet isn't on Customize")
            app.swipeSheetDown(titled: "Customize")
            XCTAssertTrue(name.disappears(), "A swipe down left the sheet up")
            XCTAssertTrue(app.lastRowClearsAddExercise(), "The created row rests under the +")
        }
    }

    /// Back in Add exercise, the search lists the exercise Create made; held, its menu offers
    /// Customize… and Delete, which asks in a centered alert and then takes it from the list and
    /// its row from the routine, its name free to create again. A built-in's menu is
    /// `RoutineDrawerUITests`'. That a delete removes its rows, and the question's count, are the
    /// package's (`RoutineStoreCustomizeTests`, `RoutineSessionExerciseTests`).
    @MainActor
    private func createdHoldMenuDeletes(in app: XCUIApplication) {
        XCTContext.runActivity(named: "A created one's hold menu deletes it, asking first") { _ in
            let count = app.exerciseRows.count
            let delete = app.buttons["picker.menu.delete"]
            _ = app.openPicker()
            app.search(for: "zq")
            let create = app.buttons["picker.create"]
            let row = app.pickerRows["Zq"]
            XCTAssertTrue(row.appears(), "The created exercise isn't in the list")
            XCTAssertTrue(row.settles(), "The created exercise's row kept moving")
            row.press(forDuration: 1)
            XCTAssertTrue(delete.appears(), "A created one's hold menu offers no Delete")
            XCTAssertTrue(
                app.buttons["Customize…"].exists,
                "A created one's hold menu offers no Customize…",
            )
            delete.tap()
            app.answerAlert("Delete Zq?", with: "Delete exercise")
            XCTAssertTrue(row.disappears(), "The deleted exercise is still listed")
            XCTAssertTrue(create.appears(), "Its name isn't free to create again")
            // Closing the search brings Close back, out of the closing field.
            app.searchButton.tap()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.settles(), "Close kept moving")
            close.tap()
            XCTAssertTrue(close.disappears(), "Close left the picker up")
            XCTAssertEqual(
                app.exerciseCount(becoming: count - 1),
                count - 1,
                "The deleted exercise's row stayed",
            )
        }
    }
}

@MainActor
extension RowDragUITests {
    /// The system's swipe actions: a swipe opens a row's Remove, a tap on Start closes it, and
    /// a full swipe deletes outright. What a delete does to a superset is
    /// `RoutineSupersetTests`', and Start going with the last row `RoutineAutosaveUITests`'.
    func deleteExercises(in app: XCUIApplication) {
        let delete = app.buttons["Remove"]
        XCTContext.runActivity(named: "A swipe opens a row, and Remove removes it") { _ in
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
            // Scrolled to the list's end, so the swipe starts on the row and not on Add
            // exercise's +, which floats over the rows' trailing end at the screen's bottom.
            app.exerciseRows.element(boundBy: 2).swipeUp()
            XCTAssertTrue(app.lastRowClearsAddExercise(), "The last row stayed under the +")
            app.lastExerciseRow.fullSwipeLeft()
            XCTAssertEqual(app.exerciseCount(becoming: 7), 7, "A full swipe did not delete")
        }
    }
}

import XCTest

/// Adding, searching, and deleting exercises, run within `testRenameAtDefaultSize` so they share
/// its launch.
extension RenameUITests {
    /// The picker opens fast and without the keyboard, search narrows it, and a pick adds a row.
    @MainActor
    func addAndSearchExercises(in app: XCUIApplication, keyboard: XCUIElement) {
        let search = app.searchFields.firstMatch
        XCTContext.runActivity(named: "Add exercise opens the picker") { _ in
            XCTAssertFalse(app.buttons["Start"].exists, "Start shows with no exercises")
            _ = app.openPicker()
            XCTAssertFalse(keyboard.exists, "Search took focus when the picker opened")
            XCTAssertEqual(app.pickerRows.firstMatch.label, "Balance board hold, Balance board")
        }
        XCTContext.runActivity(named: "Search narrows and shows an empty state") { _ in
            search.tap()
            search.typeText("curl")
            let curls = ["Biceps curl, Dumbbells", "Hammer curl, Dumbbells"]
            XCTAssertTrue(app.pickerRows[curls[0]].appears())
            XCTAssertEqual(app.pickerRows.allElementsBoundByIndex.map(\.label), curls)
            app.searchForNothing(replacing: "curl", in: search)
            XCTAssertEqual(app.pickerRows.count, 0)
            attach(named: "picker-no-results")
            // While searching, the first Close ends the search; the next closes the sheet.
            for _ in 0 ..< 2 where search.exists {
                app.buttons["Close"].firstMatch.tap()
                _ = keyboard.disappears()
            }
            XCTAssertTrue(search.disappears(), "Close left the picker open")
            XCTAssertEqual(app.exerciseRows.count, 0, "Closing the picker added an exercise")
        }
        XCTContext.runActivity(named: "Start appears with the first exercise") { _ in
            app.addExercise("Barbell bench press, Barbell, bench")
            XCTAssertTrue(app.buttons["Start"].appears())
            app.buttons["Start"].tap()
            XCTAssertEqual(app.exerciseCount(becoming: 1), 1)
            XCTAssertFalse(search.exists, "Start opened something")
        }
        XCTContext.runActivity(named: "Six adds in a row, one a duplicate") { _ in
            // Each is in the first screenful: one tap to open, one to pick.
            for label in [
                "Band pull-apart, Band",
                "Band pull-apart, Band",
                "Balance board hold, Balance board",
                "Barbell back squat, Barbell",
                "Biceps curl, Dumbbells",
            ] {
                app.addExercise(label)
            }
            app.addExercise("Push-up", searching: "push-up")
            XCTAssertEqual(app.exerciseCount(becoming: 7), 7)
            attach(named: "seven-exercises")
        }
        XCTContext.runActivity(named: "Rows read as name and equipment") { _ in
            let labels = app.exerciseRows.allElementsBoundByIndex.map(\.label)
            XCTAssertEqual(labels, [
                "Barbell bench press, Barbell, bench",
                "Band pull-apart, Band",
                "Band pull-apart, Band",
                "Balance board hold, Balance board",
                "Barbell back squat, Barbell",
                "Biceps curl, Dumbbells",
                "Push-up",
            ])
        }
    }

    /// A slow drag opens a row's Delete key, a short fast flick only opens it, a long fast swipe
    /// deletes outright, and with no rows left Start goes.
    @MainActor
    func deleteExercises(in app: XCUIApplication) {
        let delete = app.buttons["Delete"]
        XCTContext.runActivity(named: "A slow drag opens a row, and Delete deletes it") { _ in
            app.exerciseRows.element(boundBy: 1).dragLeft(by: 100, velocity: .slow)
            XCTAssertTrue(delete.appears(), "A slow drag did not open the row")
            attach(named: "row-open")
            delete.tap()
            XCTAssertEqual(app.exerciseCount(becoming: 6), 6)
            XCTAssertTrue(delete.disappears())
        }
        XCTContext.runActivity(named: "A drag right that starts on Delete closes the row") { _ in
            app.exerciseRows.element(boundBy: 0).dragLeft(by: 100, velocity: .slow)
            XCTAssertTrue(delete.appears(), "A slow drag did not open the row")
            // It lifts still over the key, where a tap would delete.
            delete.drag(by: 50, from: 0.2, velocity: 150)
            XCTAssertTrue(delete.disappears(), "Dragging right from Delete left the row open")
            let count = app.exerciseCount(becoming: 5, within: 1)
            XCTAssertEqual(count, 6, "Dragging right from Delete deleted the row")
        }
        XCTContext.runActivity(named: "A tap anywhere else closes an open row") { _ in
            let open = { app.exerciseRows.element(boundBy: 0).dragLeft(by: 100, velocity: .slow) }
            open()
            XCTAssertTrue(delete.appears(), "A slow drag did not open the row")
            let addExercise = app.buttons["Add exercise"]
            addExercise.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
                .withOffset(CGVector(dx: 0, dy: 40)).tap()
            XCTAssertTrue(delete.disappears(), "A tap on empty screen left the row open")
            open()
            XCTAssertTrue(delete.appears())
            app.exerciseRows.element(boundBy: 1).tap()
            XCTAssertTrue(delete.disappears(), "A tap on another row left the row open")
            open()
            XCTAssertTrue(delete.appears())
            _ = app.openPicker()
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(app.searchFields.firstMatch.disappears())
            XCTAssertFalse(delete.exists, "Add exercise left the row open")
            XCTAssertEqual(app.exerciseRows.count, 6, "A tap outside the row deleted something")
        }
        XCTContext.runActivity(named: "A short fast flick opens a row, never deletes it") { _ in
            let row = app.exerciseRows.element(boundBy: 0)
            row.dragLeft(by: 60, velocity: 4000)
            XCTAssertTrue(delete.appears(), "A flick did not open the row")
            // The row settles as the finger lifts, so with the key up the count is final.
            XCTAssertEqual(app.exerciseRows.count, 6, "A short flick deleted the row")
            attach(named: "row-flicked-open")
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            XCTAssertTrue(delete.disappears(), "Tapping an open row did not close it")
        }
        XCTContext.runActivity(named: "A long fast swipe deletes without the tap") { _ in
            app.lastExerciseRow.dragLeft(by: 250, velocity: 1500)
            XCTAssertEqual(app.exerciseCount(becoming: 5), 5, "A long swipe did not delete the row")
        }
        XCTContext.runActivity(named: "Deleting the last row takes Start away") { _ in
            for left in (0 ..< 5).reversed() {
                app.lastExerciseRow.dragLeft(by: 250, velocity: 1500)
                XCTAssertEqual(app.exerciseCount(becoming: left), left)
            }
            XCTAssertTrue(app.buttons["Start"].disappears(), "Start stayed with no exercises")
        }
    }
}

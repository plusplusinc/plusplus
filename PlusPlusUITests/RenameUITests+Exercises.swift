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
        readRowsAtTheListEnd(in: app)
    }

    /// The rows read as name, equipment, and plan, and at the end of the list both keys and the
    /// title stay reachable. Split from `addAndSearchExercises` so each body stays inside
    /// SwiftLint's length limit; the activities run in this order either way.
    @MainActor
    private func readRowsAtTheListEnd(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Rows read as name, equipment, and plan") { _ in
            let labels = app.exerciseRows.allElementsBoundByIndex.map(\.label)
            XCTAssertEqual(labels, [
                "Barbell bench press, Barbell, bench, 3 sets of 5 reps",
                "Band pull-apart, Band, 3 sets of 15 reps",
                "Band pull-apart, Band, 3 sets of 15 reps",
                "Balance board hold, Balance board, 3 sets of 30 seconds",
                "Barbell back squat, Barbell, 3 sets of 5 reps",
                "Biceps curl, Dumbbells, 3 sets of 12 reps",
                "Push-up, 3 sets of 10 reps",
            ])
        }
        XCTContext.runActivity(named: "An add that would hide Add exercise scrolls to it") { _ in
            // The eighth row still fits; the ninth pushes Add exercise below Start.
            app.addExercise("Balance board hold, Balance board")
            app.addExercise("Barbell back squat, Barbell")
            XCTAssertTrue(app.addExerciseClearsStart(), "The add left Add exercise behind Start")
            attach(named: "nine-exercises")
        }
        XCTContext.runActivity(named: "A tap on the small title scrolls back to the top") { _ in
            let bar = app.navigationBars.firstMatch
            let smallTitle = bar.buttons["Arm and back day"]
            XCTAssertTrue(smallTitle.appears(), "No small title in the bar at the end of the list")
            smallTitle.tap()
            XCTAssertTrue(
                reading(app.routineTitle.frame.minY >= bar.frame.maxY, becoming: true, within: 2),
                "The title did not come back below the bar",
            )
            XCTAssertTrue(smallTitle.disappears(), "The small title stayed with the title in view")
        }
    }

    /// Start rides above the keyboard while the title is edited, rather than staying behind it.
    @MainActor
    func startClearsKeyboard(in app: XCUIApplication, keyboard: XCUIElement) {
        XCTContext.runActivity(named: "Start rides above the keyboard") { _ in
            let title = app.routineTitle
            title.tap()
            XCTAssertTrue(keyboard.appears())
            let start = app.buttons["Start"]
            XCTAssertTrue(
                reading(start.frame.maxY <= keyboard.frame.minY, becoming: true, within: 2),
                "Start is behind the keyboard",
            )
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
        }
    }

    /// The system's swipe actions: a swipe opens a row's Delete, a tap elsewhere closes it, a
    /// full swipe deletes outright, and with no rows left Start goes.
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
            // Halfway between Add exercise and Start: clear of both keys' touch slop, and of
            // Start's bar, however many rows there are.
            let addExercise = app.buttons["Add exercise"]
            let gap = app.buttons["Start"].frame.minY - addExercise.frame.maxY
            addExercise.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
                .withOffset(CGVector(dx: 0, dy: gap / 2)).tap()
            XCTAssertTrue(delete.disappears(), "A tap on empty screen left the row open")
            open()
            app.buttons["Start"].tap()
            XCTAssertTrue(delete.disappears(), "A tap on Start left the row open")
            open()
            // The tap closes the row and still opens the picker.
            _ = app.openPicker()
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(app.searchFields.firstMatch.disappears())
            XCTAssertFalse(delete.exists, "Add exercise left the row open")
            let count = app.exerciseCount(becoming: 7, within: 1)
            XCTAssertEqual(count, 8, "A tap outside the row deleted it")
        }
        XCTContext.runActivity(named: "A full swipe deletes, and with no rows Start goes") { _ in
            for left in (0 ..< 8).reversed() {
                app.lastExerciseRow.fullSwipeLeft()
                XCTAssertEqual(
                    app.exerciseCount(becoming: left),
                    left,
                    "A full swipe did not delete",
                )
            }
            XCTAssertTrue(app.buttons["Start"].disappears(), "Start stayed with no exercises")
        }
    }
}

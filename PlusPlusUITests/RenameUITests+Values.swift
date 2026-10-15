import XCTest

/// A row's plan, set in its sheet, run within `testRenameAtDefaultSize` so they share its launch.
/// It starts and ends with the nine rows `addAndSearchExercises` left, the list at its top.
extension RenameUITests {
    @MainActor
    func setValues(in app: XCUIApplication, keyboard: XCUIElement) {
        let rows = app.exerciseRows
        app.addExercise("Dumbbell row, Dumbbells, bench", searching: "dumbbell row")
        app.addExercise("Pigeon stretch", searching: "pigeon")
        let (dumbbellRow, pigeon) = (rows.element(boundBy: 9), rows.element(boundBy: 10))
        XCTContext.runActivity(named: "A tap on a row opens its sheet with only its parts") { _ in
            pigeon.tap()
            XCTAssertTrue(app.planRow(.sets).appears(), "A tap on a row opened no sheet")
            XCTAssertEqual(app.planRow(.target).label, "Time, Per side")
            XCTAssertFalse(app.planRow(.weight).exists, "A stretch has a weight")
            attach(named: "sheet-pigeon")
            app.closeSheet()
            dumbbellRow.tap()
            XCTAssertEqual(app.planRow(.target).label, "Reps, Per side")
            XCTAssertEqual(app.planRow(.weight).label, "Weight, One dumbbell")
            XCTAssertEqual(app.planRow(.weight).value as? String, "Not set")
            attach(named: "sheet-row")
        }
        XCTContext.runActivity(named: "+ and − change the row's line") { _ in
            app.planRow(.target).tapKey(.increase)
            XCTAssertEqual(app.planRow(.target).value(becoming: "11 reps"), "11 reps")
            app.planRow(.weight).tapKey(.increase)
            XCTAssertEqual(app.planRow(.weight).value(becoming: "5 pounds"), "5 pounds")
            app.planRow(.sets).tapKey(.decrease)
            app.closeSheet()
            XCTAssertEqual(
                dumbbellRow.label,
                "Dumbbell row, Dumbbells, bench, 2 sets of 11 reps per side, 5 pounds",
            )
        }
        typeValues(in: app, keyboard: keyboard, pigeon: pigeon, dumbbellRow: dumbbellRow)
        XCTContext
            .runActivity(named: "More, then Delete, removes the row and closes the sheet") { _ in
                for row in [pigeon, dumbbellRow] {
                    row.tap()
                    XCTAssertTrue(app.planRow(.sets).appears())
                    app.buttons["More"].tap()
                    let delete = app.collectionViews.buttons["Delete"]
                    XCTAssertTrue(delete.appears(), "More has no Delete")
                    attach(named: "sheet-menu")
                    delete.tap()
                    XCTAssertTrue(app.planRow(.sets).disappears(), "Delete left the sheet open")
                }
                XCTAssertEqual(app.exerciseCount(becoming: 9), 9)
            }
        stepTheRightRow(in: app)
    }

    /// Two rows of one exercise keep their own values, and a bar starts at the empty bar.
    @MainActor
    private func stepTheRightRow(in app: XCUIApplication) {
        let rows = app.exerciseRows
        XCTContext.runActivity(named: "A tap opens that row's sheet alone") { _ in
            app.navigationBars.firstMatch.buttons["Arm and back day"].tap()
            let bands = (rows.element(boundBy: 1), rows.element(boundBy: 2))
            bands.1.tap()
            app.planRow(.target).tapKey(.increase)
            XCTAssertEqual(app.planRow(.target).value(becoming: "16 reps"), "16 reps")
            app.closeSheet()
            XCTAssertEqual(bands.0.label, "Band pull-apart, Band, 3 sets of 15 reps")
            XCTAssertEqual(bands.1.label, "Band pull-apart, Band, 3 sets of 16 reps")
            let bench = rows.element(boundBy: 0)
            bench.tap()
            XCTAssertEqual(app.planRow(.target).label, "Reps", "A bench press is per side")
            XCTAssertEqual(app.planRow(.weight).label, "Weight, Bar, total")
            app.planRow(.weight).tapKey(.increase)
            XCTAssertEqual(app.planRow(.weight).value(becoming: "45 pounds"), "45 pounds")
            attach(named: "sheet-bench")
            app.closeSheet()
            XCTAssertEqual(
                bench.label,
                "Barbell bench press, Barbell, bench, 3 sets of 5 reps, 45 pounds",
            )
        }
    }

    /// Typing a number: a time fills from the right and the keyboard's check ends it; a weight
    /// takes a decimal, and the sheet's Done keeps it.
    @MainActor
    private func typeValues(
        in app: XCUIApplication,
        keyboard: XCUIElement,
        pigeon: XCUIElement,
        dumbbellRow: XCUIElement,
    ) {
        XCTContext.runActivity(named: "Typing a time fills from the right") { _ in
            pigeon.tap()
            app.planRow(.target).tapKey(.value)
            XCTAssertTrue(keyboard.appears(), "A tap on the time raised no keyboard")
            app.typeText("130")
            XCTAssertEqual(app.textFields["Time"].value(becoming: "1:30"), "1:30")
            attach(named: "sheet-typing-time")
            app.buttons["Done typing"].tap()
            XCTAssertEqual(app.planRow(.target).value(becoming: "90 seconds"), "90 seconds")
            app.closeSheet()
            XCTAssertEqual(pigeon.label, "Pigeon stretch, 90 seconds per side")
        }
        XCTContext.runActivity(named: "A typed weight is kept by the sheet's Done") { _ in
            dumbbellRow.tap()
            app.planRow(.weight).tapKey(.value)
            XCTAssertTrue(keyboard.appears(), "A tap on the weight raised no keyboard")
            app.typeText("4")
            // A tap on the sheet, here beside Sets, ends typing as the keyboard's check does.
            app.planRow(.sets).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
            XCTAssertEqual(app.planRow(.weight).value(becoming: "4 pounds"), "4 pounds")
            app.planRow(.weight).tapKey(.value)
            app.typeText("42.5")
            XCTAssertEqual(app.textFields["Weight"].value(becoming: "42.5"), "42.5")
            attach(named: "sheet-typing-weight")
            app.closeSheet()
            XCTAssertEqual(
                dumbbellRow.label,
                "Dumbbell row, Dumbbells, bench, 2 sets of 11 reps per side, 42.5 pounds",
            )
        }
    }
}

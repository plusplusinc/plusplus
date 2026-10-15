import XCTest

/// A row's plan, set in its sheet, run within `testRenameAtDefaultSize` so they share its launch.
/// It starts and ends with the nine rows `addAndSearchExercises` left, the list at its top.
extension RenameUITests {
    @MainActor
    func setValues(in app: XCUIApplication) {
        let rows = app.exerciseRows
        app.addExercise("Dumbbell row, Dumbbells, bench", searching: "dumbbell row")
        app.addExercise("Pigeon stretch", searching: "pigeon")
        let (dumbbellRow, pigeon) = (rows.element(boundBy: 9), rows.element(boundBy: 10))
        XCTContext.runActivity(named: "A tap on a row opens its sheet with only its parts") { _ in
            pigeon.tap()
            XCTAssertTrue(app.planRow(.sets).appears(), "A tap on a row opened no sheet")
            XCTAssertEqual(app.planRow(.target).label, "Time")
            XCTAssertEqual(app.planRow(.target).value as? String, "60 seconds per side")
            XCTAssertFalse(app.planRow(.weight).exists, "A stretch has a weight")
            attach(named: "sheet-pigeon")
            app.closeSheet()
            dumbbellRow.tap()
            XCTAssertTrue(app.planRow(.sets).appears(), "A tap on a row opened no sheet")
            XCTAssertEqual(app.pickerWheels.count, 0, "The sheet opened with a wheel up")
            XCTAssertEqual(app.planRow(.target).label, "Reps")
            XCTAssertEqual(app.planRow(.target).value as? String, "10 reps per side")
            XCTAssertEqual(app.planRow(.weight).label, "Weight")
            XCTAssertEqual(app.planRow(.weight).value as? String, "25 pounds")
            attach(named: "sheet-row")
        }
        openOneWheelAtATime(in: app)
        XCTContext.runActivity(named: "The wheel sets the row's line once the sheet closes") { _ in
            app.pick("11", for: .target)
            XCTAssertEqual(
                app.planRow(.target).value(becoming: "11 reps per side"),
                "11 reps per side",
            )
            app.pick("30 lb", for: .weight)
            XCTAssertEqual(app.planRow(.weight).value(becoming: "30 pounds"), "30 pounds")
            app.pick("2", for: .sets)
            app.closeSheet()
            dumbbellRow
                .assertReads(
                    "Dumbbell row, Dumbbells, bench, 2 sets of 11 reps per side, 30 pounds",
                )
        }
        pickTimeAndWeight(in: app, pigeon: pigeon, dumbbellRow: dumbbellRow)
        XCTContext
            .runActivity(
                named: "More, then Delete, confirmed, removes the row and closes the sheet",
            ) { _ in
                for row in [pigeon, dumbbellRow] {
                    row.tap()
                    XCTAssertTrue(app.planRow(.sets).appears())
                    app.buttons["More"].tap()
                    let delete = app.collectionViews.buttons["Delete"]
                    XCTAssertTrue(delete.appears(), "More has no Delete")
                    attach(named: "sheet-menu")
                    delete.tap()
                    XCTAssertTrue(app.planRow(.sets).exists, "Delete went without asking")
                    let confirm = app.buttons["Delete"].firstMatch
                    XCTAssertTrue(confirm.appears(), "Delete asked nothing")
                    attach(named: "sheet-confirm-delete")
                    confirm.tap()
                    XCTAssertTrue(app.planRow(.sets).disappears(), "Delete left the sheet open")
                }
                XCTAssertEqual(app.exerciseCount(becoming: 9), 9)
            }
        stepTheRightRow(in: app)
    }

    /// A row's tap opens its wheel, closing any other; a second tap closes it.
    @MainActor
    private func openOneWheelAtATime(in app: XCUIApplication) {
        XCTContext.runActivity(named: "One wheel opens at a time") { _ in
            app.open(.sets)
            XCTAssertEqual(app.pickerWheels.firstMatch.value as? String, "3")
            attach(named: "sheet-row-sets-open")
            app.open(.target)
            XCTAssertEqual(app.pickerWheels.count, 1, "Opening Reps left Sets open")
            XCTAssertEqual(app.pickerWheels.firstMatch.value as? String, "10")
            app.planRow(.target).tap()
            XCTAssertTrue(app.pickerWheels.firstMatch.disappears(), "A second tap left it open")
        }
    }

    /// Two rows of one exercise keep their own values, and a bar starts at the empty bar.
    @MainActor
    private func stepTheRightRow(in app: XCUIApplication) {
        let rows = app.exerciseRows
        XCTContext.runActivity(named: "A tap opens that row's sheet alone") { _ in
            app.navigationBars.firstMatch.buttons["Arm and back day"].tap()
            let bands = (rows.element(boundBy: 1), rows.element(boundBy: 2))
            bands.1.tap()
            app.pick("16", for: .target)
            XCTAssertEqual(app.planRow(.target).value(becoming: "16 reps"), "16 reps")
            app.closeSheet()
            bands.0.assertReads("Band pull-apart, Band, 3 sets of 15 reps")
            bands.1.assertReads("Band pull-apart, Band, 3 sets of 16 reps")
            let bench = rows.element(boundBy: 0)
            bench.tap()
            XCTAssertEqual(app.planRow(.target).value as? String, "5 reps", "Bench is per side")
            XCTAssertEqual(app.planRow(.weight).value as? String, "45 pounds", "No empty bar")
            app.open(.weight)
            // Opening a wheel changes nothing.
            XCTAssertEqual(app.pickerWheels.firstMatch.value as? String, "45 lb")
            XCTAssertEqual(app.planRow(.weight).value as? String, "45 pounds")
            attach(named: "sheet-bench-wheel")
            app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "50 lb")
            app.planRow(.weight).tap()
            XCTAssertEqual(app.planRow(.weight).value(becoming: "50 pounds"), "50 pounds")
            attach(named: "sheet-bench")
            app.closeSheet()
            bench.assertReads("Barbell bench press, Barbell, bench, 3 sets of 5 reps, 50 pounds")
        }
    }

    /// A time picks minutes and seconds side by side.
    @MainActor
    private func pickTimeAndWeight(
        in app: XCUIApplication,
        pigeon: XCUIElement,
        dumbbellRow: XCUIElement,
    ) {
        XCTContext.runActivity(named: "A time picks minutes and seconds") { _ in
            pigeon.tap()
            app.open(.target)
            XCTAssertEqual(app.pickerWheels.count, 2, "A time has no minutes and seconds")
            attach(named: "sheet-time-wheels")
            app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "1 min")
            app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "30 s")
            XCTAssertEqual(
                app.planRow(.target).value(becoming: "90 seconds per side"),
                "90 seconds per side",
            )
            app.closeSheet()
            pigeon.assertReads("Pigeon stretch, 90 seconds per side")
        }
        XCTContext.runActivity(named: "A picked weight lands on the row") { _ in
            dumbbellRow.tap()
            app.pick("40 lb", for: .weight)
            app.pick("12", for: .target)
            attach(named: "sheet-weight-picked")
            app.closeSheet()
            dumbbellRow
                .assertReads(
                    "Dumbbell row, Dumbbells, bench, 2 sets of 12 reps per side, 40 pounds",
                )
        }
    }
}

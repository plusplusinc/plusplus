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
            XCTAssertEqual(app.planRow(.target).label, "Time, Per side")
            XCTAssertFalse(app.planRow(.weight).exists, "A stretch has a weight")
            attach(named: "sheet-pigeon")
            app.closeSheet()
            dumbbellRow.tap()
            XCTAssertEqual(app.planRow(.target).label, "Reps, Per side")
            XCTAssertEqual(app.planRow(.weight).label, "Weight, One dumbbell")
            XCTAssertEqual(app.planRow(.weight).value as? String, "25 pounds")
            attach(named: "sheet-row")
        }
        XCTContext.runActivity(named: "Wheels change the row's line once the sheet is down") { _ in
            app.pick("11", for: .target)
            XCTAssertEqual(app.planRow(.target).value(becoming: "11 reps"), "11 reps")
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
            XCTAssertEqual(app.planRow(.target).label, "Reps", "A bench press is per side")
            XCTAssertEqual(app.planRow(.weight).label, "Weight, Bar, total")
            XCTAssertEqual(app.planRow(.weight).value as? String, "45 pounds", "No empty bar")
            app.planRow(.weight).tap()
            // Opening the wheel changes nothing.
            XCTAssertTrue(app.pickerWheels.firstMatch.appears(), "No weight wheel")
            XCTAssertEqual(app.pickerWheels.firstMatch.value as? String, "45 lb")
            attach(named: "sheet-bench-wheel")
            app.planRow(.weight).tap()
            app.pick("50 lb", for: .weight)
            XCTAssertEqual(app.planRow(.weight).value(becoming: "50 pounds"), "50 pounds")
            attach(named: "sheet-bench")
            app.closeSheet()
            bench.assertReads("Barbell bench press, Barbell, bench, 3 sets of 5 reps, 50 pounds")
        }
    }

    /// A time picks minutes and seconds side by side; a tap on the sheet's empty space closes a
    /// wheel.
    @MainActor
    private func pickTimeAndWeight(
        in app: XCUIApplication,
        pigeon: XCUIElement,
        dumbbellRow: XCUIElement,
    ) {
        XCTContext.runActivity(named: "A time picks minutes and seconds") { _ in
            pigeon.tap()
            app.planRow(.target).tap()
            let wheels = app.pickerWheels
            XCTAssertEqual(wheels.count, 2, "A time has no minutes and seconds")
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: "1 min")
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: "30 s")
            XCTAssertEqual(app.planRow(.target).value(becoming: "90 seconds"), "90 seconds")
            attach(named: "sheet-time-wheels")
            // A tap on the sheet's empty space, here the gap under Sets, closes the wheel.
            app.planRow(.sets).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
                .withOffset(CGVector(dx: 0, dy: 8)).tap()
            XCTAssertTrue(wheels.firstMatch.disappears(), "A tap on the sheet left the wheel open")
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

import XCTest

extension RoutineAutosaveUITests {
    /// The created exercise's row, as the routine reads it.
    static let ringRow = "Ring row with rotation, 3 sets of 10 reps"

    /// A search with no exact name offers Create as the list's last row, and one with no match
    /// narrows the list down to it; Create stores the exercise under the search text and pushes
    /// its Customize form inside the sheet, with no Save; the two checklists mark what is
    /// checked for VoiceOver and the form reads it back; and Done closes the sheet on a routine
    /// with the row in. The relaunch after it lists the exercise with the equipment checked
    /// here, so each change was stored as made. The rule for Create, the derived plan, and the
    /// store's round trip are the package's (`CreatedExerciseTests`, `RoutineStoreExerciseTests`,
    /// `RoutineSessionTests`); this holds the wire through the sheet, its search, and its pushed
    /// screens.
    @MainActor
    func createAnExercise(in app: XCUIApplication) {
        XCTContext
            .runActivity(named: "An exercise created from the search joins the routine") { _ in
                let search = app.openPicker()
                app.search(for: "Ring")
                let create = app.buttons["picker.create"]
                XCTAssertEqual(
                    create.label(becoming: "Create \u{201C}Ring\u{201D}"),
                    "Create \u{201C}Ring\u{201D}",
                )
                let lastMatch = app.pickerRows.element(boundBy: app.pickerRows.count - 1)
                XCTAssertGreaterThan(
                    create.frame.midY,
                    lastMatch.frame.midY,
                    "Create is not below the matches",
                )
                app.typeIntoSearch(" row with rotation")
                let created = "Create \u{201C}Ring row with rotation\u{201D}"
                XCTAssertEqual(create.label(becoming: created), created)
                XCTAssertEqual(app.pickerRows.count, 0, "Rows other than Create match")
                attach(named: "picker-create-only")
                let count = app.exerciseRows.count
                create.tap()
                let name = app.textFields["customize.name"]
                XCTAssertTrue(name.appears(), "Create pushed no Customize form")
                XCTAssertEqual(name.value as? String, "Ring row with rotation")
                XCTAssertFalse(app.buttons["Save"].exists, "Customize has a Save")
                check("Back", in: app, from: "Muscle groups, None")
                check("Rings", in: app, from: "Equipment, Bodyweight")
                XCTAssertTrue(app.buttons["Muscle groups, Back"].exists)
                XCTAssertTrue(app.buttons["Equipment, Rings"].exists)
                XCTAssertTrue(app.buttons["Measure, Reps"].exists, "Measure reads no value")
                XCTAssertEqual(app.switches["Per side"].value as? String, "0")
                attach(named: "customize-form")
                app.buttons["Done"].tap()
                // The pushed form hides the list's search, so the form going is the sheet's.
                XCTAssertTrue(name.disappears(), "Done left Customize up")
                XCTAssertFalse(search.exists, "Done went back to the list, not out of the sheet")
                XCTAssertEqual(
                    app.exerciseCount(becoming: count + 1),
                    count + 1,
                    "Create added no row",
                )
                XCTAssertEqual(app.exerciseRowLabels.last, Self.ringRow)
            }
    }

    /// On an empty routine, an exercise created in Add exercise and deleted from its Customize
    /// form there takes its row with it, and the routine shows empty again once the sheet
    /// closes: No exercises, no Start, and the + back down where it sat before. Only the
    /// running app shows the screen taking up the stored routine from inside the sheet; that a
    /// delete removes its rows is the package's (`RoutineStoreCustomizeTests`).
    @MainActor
    func deleteInPickerEmptiesRoutine(in app: XCUIApplication) {
        XCTContext.runActivity(named: "A Delete in Add exercise that empties the routine") { _ in
            let plus = app.buttons["Add exercise"]
            XCTAssertEqual(app.exerciseRows.count, 0, "The routine isn't empty to start")
            XCTAssertTrue(plus.settles(), "The + kept moving")
            let low = plus.frame
            _ = app.openPicker()
            app.search(for: "zq")
            let create = app.buttons["picker.create"]
            XCTAssertTrue(create.appears(), "The search offered no Create")
            create.tap()
            let name = app.textFields["customize.name"]
            XCTAssertTrue(name.appears(), "Create pushed no Customize form")
            XCTAssertEqual(app.exerciseCount(becoming: 1), 1, "Create added no row")
            // It arrives with the push.
            let delete = app.buttons["Delete exercise"]
            XCTAssertTrue(delete.settles(), "Delete exercise kept moving")
            delete.tap()
            app.answerAlert("Delete Zq?", with: "Delete exercise")
            XCTAssertTrue(name.disappears(), "Delete didn't come back to the list")
            XCTAssertEqual(app.exerciseCount(becoming: 0), 0, "The deleted exercise's row stayed")
            // The search is still open, over Close.
            app.searchButton.tap()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.appears(), "Closing the search brought back no Close")
            // It comes back out of the closing field.
            XCTAssertTrue(close.settles(), "Close kept moving")
            close.tap()
            XCTAssertTrue(close.disappears(), "Close left the picker up")
            XCTAssertTrue(app.noExercises.appears(), "No exercises did not return")
            XCTAssertFalse(app.buttons["Start"].exists, "Start stayed with no exercises")
            XCTAssertTrue(plus.settles(), "The + kept moving")
            XCTAssertEqual(plus.frame.minY, low.minY, accuracy: 1, "The + stayed up with no Start")
            attach(named: "deleted-in-picker")
        }
    }

    /// Opens the row labeled `row`, checks `item` there, and comes back to the form.
    @MainActor
    private func check(_ item: String, in app: XCUIApplication, from row: String) {
        app.buttons[row].tap()
        let button = app.buttons[item]
        XCTAssertTrue(button.appears(), "\(row) opened no list")
        button.tap()
        XCTAssertTrue(
            reading(button.isSelected, becoming: true, within: 2),
            "\(item) does not read as selected",
        )
        app.tapBack()
        XCTAssertTrue(button.disappears(), "Back left the list up")
    }
}

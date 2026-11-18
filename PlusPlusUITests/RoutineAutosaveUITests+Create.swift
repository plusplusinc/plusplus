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

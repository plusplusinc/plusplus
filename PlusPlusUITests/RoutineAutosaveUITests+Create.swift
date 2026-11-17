import XCTest

extension RoutineAutosaveUITests {
    /// The created exercise's row, as the routine reads it.
    static let ringRow = "Ring row with rotation, 3 sets of 10 reps"

    /// A search with no exact name offers Create as the list's last row, and one with no match
    /// narrows the list down to it; Create pushes New exercise with the search text, the two
    /// checklists mark what is checked for VoiceOver and the form reads it back, and Add puts
    /// the row in. The rule for Create, the derived plan, and the store's round trip are the
    /// package's (`CreatedExerciseTests`, `RoutineStoreExerciseTests`, `RoutineSessionTests`);
    /// this holds the wire through the sheet, its search, and its pushed screens, and the
    /// relaunch after it brings the exercise back.
    @MainActor
    func createAnExercise(in app: XCUIApplication) {
        XCTContext
            .runActivity(named: "An exercise created from the search joins the routine") { _ in
                let search = app.openPicker()
                search.tap()
                search.typeText("Ring")
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
                search.typeText(" row with rotation")
                let created = "Create \u{201C}Ring row with rotation\u{201D}"
                XCTAssertEqual(create.label(becoming: created), created)
                XCTAssertEqual(app.pickerRows.count, 0, "Rows other than Create match")
                attach(named: "picker-create-only")
                create.tap()
                let name = app.textFields["newExercise.name"]
                XCTAssertTrue(name.appears(), "Create opened no form")
                XCTAssertEqual(name.value as? String, "Ring row with rotation")
                cancelAndCreateAgain(in: app, search: search, create: create, expecting: created)
                let add = app.buttons["Add"]
                XCTAssertFalse(add.isEnabled, "Add is on with no muscle group")
                check("Back", in: app, from: "Muscle groups, Choose")
                check("Rings", in: app, from: "Equipment, Bodyweight")
                XCTAssertTrue(app.buttons["Muscle groups, Back"].exists)
                XCTAssertTrue(app.buttons["Equipment, Rings"].exists)
                XCTAssertTrue(app.buttons["Measure, Reps"].exists, "Measure reads no value")
                XCTAssertEqual(app.switches["Per side"].value as? String, "0")
                attach(named: "new-exercise-form")
                let count = app.exerciseRows.count
                add.tap()
                XCTAssertTrue(search.disappears(), "Add left the picker open")
                XCTAssertEqual(
                    app.exerciseCount(becoming: count + 1),
                    count + 1,
                    "Add added no row",
                )
                XCTAssertEqual(app.exerciseRowLabels.last, Self.ringRow)
            }
    }

    /// Cancel on the form comes back to the search as it was, its text kept and the list still
    /// the one Create row, so nothing was created; Create then opens the form again. Only the
    /// running app shows the sheet's own stack popping back to a search that kept its text.
    @MainActor
    private func cancelAndCreateAgain(
        in app: XCUIApplication,
        search: XCUIElement,
        create: XCUIElement,
        expecting created: String,
    ) {
        let name = app.textFields["newExercise.name"]
        app.buttons["Cancel"].tap()
        XCTAssertTrue(name.disappears(), "Cancel left the form up")
        XCTAssertEqual(search.value(becoming: "Ring row with rotation"), "Ring row with rotation")
        XCTAssertEqual(create.label(becoming: created), created)
        XCTAssertEqual(app.pickerRows.count, 0, "Cancel left an exercise in the list")
        XCTAssertTrue(create.settles(), "Create is still moving after Cancel")
        create.tap()
        XCTAssertTrue(name.appears(), "Create opened no form after Cancel")
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
        app.buttons["BackButton"].tap()
        XCTAssertTrue(button.disappears(), "Back left the list up")
    }
}

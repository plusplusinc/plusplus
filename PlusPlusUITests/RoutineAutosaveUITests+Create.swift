import XCTest

extension RoutineAutosaveUITests {
    /// The created exercise's row, as the routine reads it.
    static let ringRow = "Ring row with rotation, 3 sets of 10 reps"

    /// A search with no exact name offers Create as the list's last row, and one with no match
    /// narrows the list down to it; Create stores the exercise under the search text, closes
    /// Add exercise, and adds its row; then the row's own sheet opens by itself on the
    /// exercise's Customize form, with no Save and no Done; the two checklists mark what is
    /// checked for VoiceOver and the form reads it back; back goes to the row's values, and
    /// Close leaves the routine with the row in. The relaunch after it lists the exercise with
    /// the equipment checked here, so each change was stored as made. The rule for Create, the
    /// derived plan, and the store's round trip are the package's (`CreatedExerciseTests`,
    /// `StoreExerciseTests`, `RoutineSessionTests`); this holds the wire through the
    /// sheets, the search, and the pushed screens.
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
                XCTAssertTrue(search.disappears(), "Create left Add exercise up")
                XCTAssertEqual(
                    app.exerciseCount(becoming: count + 1),
                    count + 1,
                    "Create added no row",
                )
                let name = app.textFields["customize.name"]
                XCTAssertTrue(app.createdSheetOpens(), "The created row's sheet isn't on Customize")
                XCTAssertEqual(name.value as? String, "Ring row with rotation")
                XCTAssertFalse(app.buttons["Save"].exists, "Customize has a Save")
                XCTAssertFalse(app.buttons["Done"].exists, "Create's Customize has a Done")
                check("Back", in: app, from: "Muscle groups, None")
                // In view in the half sheet, and holds no weight, so the row reads no load.
                check("Bench", in: app, from: "Equipment, Bodyweight")
                XCTAssertTrue(app.buttons["Muscle groups, Back"].exists)
                XCTAssertTrue(app.buttons["Equipment, Bench"].exists)
                XCTAssertTrue(app.buttons["Measure, Reps"].exists, "Measure reads no value")
                XCTAssertEqual(app.switches["Per side"].value as? String, "0")
                attach(named: "customize-form")
                app.tapBack()
                let sets = app.buttons["Sets"]
                XCTAssertTrue(sets.appears(), "Back didn't come to the row's values")
                app.buttons["Close"].tap()
                XCTAssertTrue(sets.disappears(), "Close left the sheet up")
                XCTAssertEqual(app.exerciseRowLabels.last, Self.ringRow)
            }
    }

    /// On an empty routine, an exercise created in Add exercise lands as the first row, and
    /// its sheet opens on Customize; deleted there, with a question naming this routine, it
    /// shuts the sheet, and only then takes its row, and the routine shows empty again: No
    /// exercises, no Start, and the + back down where it sat before. Only the running app shows
    /// the screen taking up the stored routine from inside the sheet; that a delete removes its
    /// rows, and the question's wording, are the package's (`StoreCustomizeTests`,
    /// `DeleteQuestionTests`).
    @MainActor
    func deleteCreatedEmptiesRoutine(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Deleting a created exercise that empties the routine") { _ in
            let plus = app.buttons["Add exercise"]
            XCTAssertEqual(app.exerciseRows.count, 0, "The routine isn't empty to start")
            XCTAssertTrue(plus.settles(), "The + kept moving")
            let low = plus.frame
            _ = app.openPicker()
            app.search(for: "zq")
            let create = app.buttons["picker.create"]
            XCTAssertTrue(create.appears(), "The search offered no Create")
            create.tap()
            XCTAssertEqual(app.exerciseCount(becoming: 1), 1, "Create added no row")
            let name = app.textFields["customize.name"]
            XCTAssertTrue(app.createdSheetOpens(), "The created row's sheet isn't on Customize")
            // Below the half sheet's fold, out of the tree until the form scrolls to it.
            app.collectionViews.containing(.textField, identifier: "customize.name").firstMatch
                .swipeUp()
            let delete = app.buttons["Delete exercise"]
            XCTAssertTrue(delete.settles(), "Delete exercise kept moving")
            delete.tap()
            let message = app.answerAlert("Delete Zq?", with: "Delete exercise")
            XCTAssertTrue(
                message.hasPrefix("It will be removed from this workout."),
                "The question doesn't name the open routine: \(message)",
            )
            XCTAssertTrue(name.disappears(), "Delete left the sheet up")
            // The row leaves once the sheet has gone, a rest after it.
            XCTAssertEqual(app.exerciseRows.count, 1, "The row went before the sheet had gone")
            XCTAssertEqual(app.exerciseCount(becoming: 0), 0, "The deleted exercise's row stayed")
            XCTAssertTrue(app.noExercises.appears(), "No exercises did not return")
            // A beat after the row, as after Remove.
            XCTAssertTrue(app.buttons["Start"].disappears(), "Start stayed with no exercises")
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

import XCTest

@MainActor
extension RoutineDrawerUITests {
    /// A routine row's More menu offers Customize…, which pushes the exercise's Customize form
    /// inside the sheet: a built-in's opens with its name and ends in Clear customizations, not
    /// Delete, disabled while nothing is changed. Arms checked, Clear asks first in a centered
    /// alert, saying what changed; confirmed, the form reads as shipped; back comes to the sheet.
    /// What a customize or clear does to the routines, and the question's wording, are the
    /// package's (`RoutineStoreBuiltInTests`, `RoutineSessionExerciseTests`,
    /// `CustomizationTests`); this holds the wire through the menu, the push, the checklist, and
    /// the alert, which only the running app composes.
    func rowCustomizes(in app: XCUIApplication) {
        let sets = app.buttons["Sets"]
        let clear = app.buttons["Clear customizations"]
        XCTContext.runActivity(named: "A row's More menu opens its exercise's Customize") { _ in
            app.exerciseRows.element(boundBy: 0).tap()
            XCTAssertTrue(sets.appears(), "Tapping a row opened no sheet")
            app.buttons["More"].tap()
            let customize = app.buttons["Customize…"]
            XCTAssertTrue(customize.appears(), "The More menu offers no Customize…")
            XCTAssertTrue(app.buttons["Remove"].exists, "The More menu offers no Remove")
            customize.tap()
            let name = app.textFields["customize.name"]
            XCTAssertTrue(name.appears(), "Customize… opened no form")
            XCTAssertEqual(
                name.value as? String,
                "Barbell bench press",
                "A built-in's form doesn't open with its name",
            )
            // Clear is below the sheet's fold, out of the tree until the form scrolls to it.
            let form = app.collectionViews.containing(.textField, identifier: "customize.name")
            form.firstMatch.swipeUp()
            XCTAssertTrue(clear.appears(), "A built-in's form doesn't end in Clear customizations")
            XCTAssertFalse(clear.isEnabled, "Clear customizations is enabled with nothing changed")
            XCTAssertFalse(app.buttons["Delete exercise"].exists, "A built-in's form offers Delete")
        }
        XCTContext.runActivity(named: "Clear customizations asks, then puts it back") { _ in
            app.buttons["Muscle groups, Chest"].tap()
            let arms = app.buttons["Arms"]
            XCTAssertTrue(arms.appears(), "Muscle groups opened no list")
            arms.tap()
            XCTAssertTrue(reading(arms.isSelected, becoming: true, within: 2), "Arms isn't checked")
            app.tapBack()
            let groups = app.buttons["Muscle groups, Chest, arms"]
            XCTAssertTrue(groups.appears(), "The form doesn't read the new group")
            XCTAssertTrue(reading(clear.isEnabled, becoming: true, within: 2), "Clear stayed off")
            clear.tap()
            let message = app.answerAlert(
                "Clear your customizations to Barbell bench press?",
                with: "Clear customizations",
            )
            XCTAssertTrue(message.contains("Arms added"), "The question doesn't say what changed")
            XCTAssertTrue(app.buttons["Muscle groups, Chest"].appears(), "Clear left Arms")
            XCTAssertFalse(
                reading(clear.isEnabled, becoming: false, within: 2),
                "Clear customizations is enabled once cleared",
            )
            app.tapBack()
            XCTAssertTrue(sets.appears(), "Back didn't come to the row's sheet")
            app.buttons["Close"].tap()
            XCTAssertTrue(sets.disappears(), "Close left the sheet up")
        }
    }

    /// In Add exercise, holding a row opens the system's context menu instead of adding it: a
    /// built-in's offers Customize… alone, which pushes its form, and back finds
    /// the list. Create closes the sheet, adds the row, and opens the row's own sheet on the
    /// exercise's form, which a swipe down closes with the row left in. Back in Add exercise,
    /// the search lists it; held, it also offers Delete, which asks in a centered alert, naming
    /// the routine behind the sheet, and then takes it from the list and its row from the
    /// routine, its name free to create again. That a delete removes its rows, and the
    /// question's wording, are the package's (`RoutineStoreCustomizeTests`,
    /// `RoutineSessionExerciseTests`, `DeleteQuestionTests`).
    func holdMenuCustomizesAndDeletes(in app: XCUIApplication) {
        let name = app.textFields["customize.name"]
        let customize = app.buttons["Customize…"]
        let delete = app.buttons["picker.menu.delete"]
        let count = app.exerciseRows.count
        XCTContext.runActivity(named: "A built-in's hold menu offers Customize… alone") { _ in
            _ = app.openPicker()
            let first = app.pickerRows.firstMatch
            XCTAssertTrue(first.appears(), "Add exercise lists nothing")
            XCTAssertTrue(first.settles(), "The row kept moving")
            let label = first.label
            first.press(forDuration: 1)
            XCTAssertTrue(customize.appears(), "Holding a row opened no menu")
            XCTAssertFalse(delete.exists, "A built-in's hold menu offers Delete")
            customize.tap()
            XCTAssertTrue(name.appears(), "Customize… opened no form")
            let exercise = name.value as? String ?? ""
            XCTAssertTrue(label.hasPrefix(exercise), "The form isn't the held row's exercise")
            app.tapBack()
            XCTAssertTrue(first.appears(), "Back didn't come to the list")
            XCTAssertEqual(app.exerciseRows.count, count, "The hold added the exercise")
        }
        createdSheetSwipesDown(in: app, from: count)
        XCTContext.runActivity(named: "A created one's hold menu deletes it, asking first") { _ in
            _ = app.openPicker()
            app.search(for: "zq")
            let create = app.buttons["picker.create"]
            let row = app.pickerRows["Zq"]
            XCTAssertTrue(row.appears(), "The created exercise isn't in the list")
            XCTAssertTrue(row.settles(), "The created exercise's row kept moving")
            row.press(forDuration: 1)
            XCTAssertTrue(delete.appears(), "A created one's hold menu offers no Delete")
            XCTAssertTrue(customize.exists, "A created one's hold menu offers no Customize…")
            delete.tap()
            let message = app.answerAlert("Delete Zq?", with: "Delete exercise")
            XCTAssertTrue(
                message.hasPrefix("It will be removed from this routine."),
                "The question doesn't name the routine behind the sheet: \(message)",
            )
            XCTAssertTrue(row.disappears(), "The deleted exercise is still listed")
            XCTAssertTrue(create.appears(), "Its name isn't free to create again")
            // Closing the search brings Close back, out of the closing field.
            app.searchButton.tap()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.settles(), "Close kept moving")
            close.tap()
            XCTAssertTrue(close.disappears(), "Close left the picker up")
            XCTAssertEqual(
                app.exerciseCount(becoming: count),
                count,
                "The deleted exercise's row stayed",
            )
        }
    }

    /// From Add exercise's list, Create "Zq" on a routine of `count` rows: the sheet closes, the
    /// row goes in, and its own sheet opens on Customize; a swipe down closes it, the row kept.
    private func createdSheetSwipesDown(in app: XCUIApplication, from count: Int) {
        XCTContext.runActivity(named: "Create's sheet swipes down, leaving its row") { _ in
            app.search(for: "zq")
            let create = app.buttons["picker.create"]
            XCTAssertTrue(create.appears(), "The search offered no Create")
            create.tap()
            let name = app.textFields["customize.name"]
            XCTAssertTrue(app.createdSheetOpens(), "The created row's sheet isn't on Customize")
            XCTAssertEqual(app.exerciseRows.count, count + 1, "Create added no row")
            app.swipeSheetDown(titled: "Customize")
            XCTAssertTrue(name.disappears(), "A swipe down left the sheet up")
            XCTAssertEqual(app.exerciseRows.count, count + 1, "The swipe down took the row")
        }
    }
}

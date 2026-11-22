import XCTest

/// Add exercise's muscle filter at the largest text size, run within the picker's audit
/// (`auditRowsAndPicker`), as VoiceOver reads it. The parts' look at AX5 is
/// `ExerciseListSnapshotTests`'; the reading and the sheet over the picker are the app's.
@MainActor
extension TitleWrappingUITests {
    /// The buttons by their filters' names; a chip selected once chosen; the button's choice as
    /// its value, and selected; the Muscle sheet and the filtered list with its count line pass
    /// the audit. Clear leaves no filter on.
    func filterAtAX5(in app: XCUIApplication) throws {
        let muscle = app.buttons["Muscle"]
        XCTAssertTrue(app.buttons["Kind"].exists && app.buttons["Equipment"].exists)
        XCTAssertEqual(muscle.value as? String, "", "Muscle reads a choice with none chosen")
        muscle.tap()
        // The chip, not the bar's back button, which shares its name.
        let back = app.scrollViews.buttons["Back"]
        XCTAssertTrue(back.appears(), "Muscle opened no sheet of chips")
        // The system draws the floating sheet at about 96% of the size it lays out, so the
        // audit reads its widest words, the title and Shoulders, as clipped where they show
        // whole; what it finds outside the sheet stands.
        let sheet = app.scrollViews.containing(NSPredicate(format: "label == 'Done'")).firstMatch
        let chips = sheet.frame
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            guard issue.auditType == .textClipped, let element = issue.element else { return false }
            return chips.contains(element.frame)
        }
        back.tap()
        XCTAssertTrue(reading(back.isSelected, becoming: true, within: 2), "Back isn't selected")
        app.buttons["Done"].tap()
        XCTAssertTrue(back.disappears(), "Done left the chips up")
        XCTAssertEqual(muscle.value(becoming: "Back"), "Back")
        XCTAssertTrue(muscle.isSelected, "Muscle isn't selected with Back chosen")
        let clear = app.buttons["Clear filters"]
        XCTAssertTrue(clear.exists, "No Clear under the filter")
        attach(named: "picker-filtered-ax5")
        try auditBelowTheBarChrome(in: app)
        clear.tap()
        XCTAssertTrue(clear.disappears(), "Clear left a filter on")
    }

    /// The audit with Add exercise's bar in view, as it is once a sheet of chips has raised it
    /// to full height: passed over, the bar's title (`auditBelowTheBar` says why) and the bar's
    /// glass buttons, which the audit flags as fixed size without naming an element. With a
    /// sheet over the bar, nothing is flagged unnamed.
    private func auditBelowTheBarChrome(in app: XCUIApplication) throws {
        let bar = app.navigationBars.firstMatch.frame
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            guard let element = issue.element else { return issue.auditType == .dynamicType }
            return bar.contains(element.frame)
        }
    }
}

import XCTest

/// The title at the largest accessibility text size, where it wraps. VoiceOver frames the field,
/// so every line it shows, the default drawn behind an empty field included, has to sit inside
/// the field's frame. Lines are read from the pixels between the bar and "Add exercise". Where
/// the `_` draws on a wrapped name is snapshot-tested.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class TitleWrappingUITests: XCTestCase {
    /// Three lines at AX5.
    private static let threeLines = "Hot beat drills and abs"

    @MainActor
    func testWrappedTitleAtLargestTextSize() throws {
        let app = XCUIApplication()
        let title = app.launchNewRoutine(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let addExercise = app.buttons["Add exercise"]
        let keyboard = app.keyboards.element

        try XCTContext.runActivity(named: "The field covers the wrapped default") { _ in
            try assertLinesInsideField(title, above: addExercise, lines: 2, "default at rest")
            title.tap()
            XCTAssertTrue(keyboard.appears())
            try assertLinesInsideField(title, above: addExercise, lines: 2, "default, editing")
        }

        try XCTContext.runActivity(named: "The field covers a long name while editing") { _ in
            title.typeText(Self.threeLines)
            XCTAssertEqual(title.value(becoming: Self.threeLines), Self.threeLines)
            try assertLinesInsideField(title, above: addExercise, lines: 3, "long name, editing")
        }

        try XCTContext.runActivity(named: "The field covers a long name") { _ in
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
            XCTAssertEqual(title.value as? String, Self.threeLines)
            try assertLinesInsideField(title, above: addExercise, lines: 3, "long name at rest")
        }

        try XCTContext.runActivity(named: "A cleared name restores the wrapped default") { _ in
            title.tap()
            XCTAssertTrue(keyboard.appears())
            // The app moves the caret to the end after focus lands, which can come after keys
            // sent at once.
            let (field, button) = (title.frame, addExercise.frame)
            _ = try Ink.withCursor { try read(field, above: button) } until: { ink, cursor in
                ink.missAtEnd(cursor)
            }
            // Deleting from the end, not ⌘A: on Xcode Cloud, ⌘A sent here hid the keyboard and
            // selected nothing.
            let delete = XCUIKeyboardKey.delete.rawValue
            title.typeText(String(repeating: delete, count: Self.threeLines.count))
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            try assertLinesInsideField(title, above: addExercise, lines: 2, "cleared, editing")
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
            XCTAssertEqual(title.value as? String, "New routine")
            try assertLinesInsideField(title, above: addExercise, lines: 2, "cleared, at rest")
        }

        try auditRowsAndPicker(in: app)
        assertAddClearsStartAtTheEnd(in: app, keyboard: keyboard, addExercise: addExercise)
        XCTContext.runActivity(named: "A row drags at the largest text size") { _ in
            let rows = app.exerciseRows
            let (first, last) = (rows.element(boundBy: 0), rows.element(boundBy: 1))
            // Its card's top, half the held row's height above the finger, clears the first
            // row's middle. Kept below the bar, where a release would put it back.
            let bar = app.navigationBars.firstMatch.frame.maxY
            let target = app.point(x: last.frame.midX, y: max(first.frame.midY, bar + 70))
            last.liftPoint.holdAndDrag(to: target)
            let moved = ["Dumbbell bench press", "Kneeling hip flexor stretch"]
            XCTAssertEqual(reading(app.exerciseNames, becoming: moved, within: 2), moved)
            attach(named: "reorder-ax5")
        }
    }

    /// Rows, a row's sheet with a stepper open, and the picker, with and without results, pass
    /// the audit at this text size.
    @MainActor
    private func auditRowsAndPicker(in app: XCUIApplication) throws {
        let name = "Rows, a sheet, and the picker at AX5 pass the audit"
        try XCTContext.runActivity(named: name) { _ in
            app.addExercise("Kneeling hip flexor stretch", searching: "kneeling")
            XCTAssertTrue(app.buttons["Start"].appears())
            attach(named: "rail-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            app.exerciseRows.firstMatch.tap()
            let time = app.buttons["Time"]
            XCTAssertTrue(time.appears(), "Tapping a row opened no sheet")
            time.tap()
            XCTAssertTrue(app.buttons["Increase"].appears(), "Tapping Time opened no stepper")
            // Audited expanded: at half height the audit reports the open row's value as
            // clipped, though it draws in full, as the screenshot shows.
            attach(named: "sheet-ax5")
            let grabber = app.buttons["Sheet Grabber"]
            grabber.tap()
            XCTAssertEqual(grabber.value(becoming: "Expanded"), "Expanded")
            attach(named: "sheet-expanded-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            app.buttons["Close"].tap()
            XCTAssertTrue(time.disappears(), "Close left the sheet up")
            let search = app.openPicker()
            attach(named: "picker-ax5")
            // Audited in use: at rest, the system search bar reports that it cannot scale, with
            // no element named, though it draws at this size, as the screenshot shows.
            search.tap()
            search.typeText("curl")
            XCTAssertTrue(app.pickerRows["Biceps curl, Dumbbells"].appears())
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            app.searchForNothing(replacing: "curl", in: search)
            attach(named: "picker-no-results-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
        }
    }

    /// At this size the second row pushes Add exercise below Start, so an add has to scroll to
    /// the end of the list, where the key clears Start with the screen's spacing to spare.
    @MainActor
    private func assertAddClearsStartAtTheEnd(
        in app: XCUIApplication,
        keyboard: XCUIElement,
        addExercise: XCUIElement,
    ) {
        XCTContext.runActivity(named: "At the end of a long list, Add exercise clears Start") { _ in
            let search = app.searchFields.firstMatch
            // While searching, the first Close ends the search; the next closes the sheet.
            for _ in 0 ..< 2 where search.exists {
                app.buttons["Close"].firstMatch.tap()
                _ = keyboard.disappears()
            }
            app.addExercise("Dumbbell bench press, Dumbbells, bench", searching: "dumbbell bench")
            XCTAssertTrue(app.addExerciseClearsStart(), "The add left Add exercise behind Start")
            attach(named: "rail-after-add-ax5")
            // The last row: the first, its plan making it taller, has its middle under the bar.
            app.lastExerciseRow.swipeOpen()
            XCTAssertTrue(app.buttons["Delete"].appears(), "A swipe did not open the row")
            app.swipeUp()
            XCTAssertTrue(app.buttons["Delete"].disappears(), "A scroll left the row open")
            app.swipeUp()
            let start = app.buttons["Start"]
            XCTAssertTrue(start.appears())
            attach(named: "rail-end-ax5")
            // 16pt, the screen's spacing, give or take rounding.
            XCTAssertGreaterThanOrEqual(
                start.frame.minY - addExercise.frame.maxY,
                15.5,
                "Add exercise does not clear Start with room to spare",
            )
        }
    }

    /// Every line of text between the bar and "Add exercise" lies inside the field.
    @MainActor
    private func assertLinesInsideField(
        _ title: XCUIElement,
        above addExercise: XCUIElement,
        lines expected: Int,
        _ label: String,
        line: UInt = #line,
    ) throws {
        let field = title.frame
        let button = addExercise.frame
        // The value can change a frame before the lines are drawn.
        let drawn = Date.now.addingTimeInterval(2)
        var ink = try read(field, above: button)
        while ink.lines.count != expected, Date.now < drawn {
            ink = try read(field, above: button)
        }
        attach(ink.shot.screenshot, named: label)
        // The strip was placed by the frame read before the shot.
        XCTAssertEqual(title.frame, field, "\(label): the field moved while read", line: line)
        XCTAssertEqual(ink.lines.count, expected, "\(label): line count", line: line)
        for (index, text) in ink.lines.enumerated() {
            XCTAssertGreaterThanOrEqual(
                text.points.lowerBound,
                field.minY - 1,
                "\(label): line \(index + 1) starts above the field \(field)",
                line: line,
            )
            XCTAssertLessThanOrEqual(
                text.points.upperBound,
                field.maxY + 1,
                "\(label): line \(index + 1) ends below the field \(field)",
                line: line,
            )
        }
        XCTAssertLessThanOrEqual(field.maxY, button.minY, "\(label): field overlaps the button")
    }

    /// The ink in the field's column, from just under the bar down to "Add exercise". The strip
    /// starts above the field, on plain background.
    @MainActor
    private func read(_ field: CGRect, above button: CGRect) throws -> Ink {
        let top = field.minY - 16
        let strip = CGRect(x: field.minX, y: top, width: field.width, height: button.minY - 1 - top)
        return try TitleShot().ink(in: strip, background: strip.origin)
    }
}

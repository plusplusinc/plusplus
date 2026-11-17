import XCTest

/// The title at the largest accessibility text size, where it wraps. VoiceOver frames the field,
/// so every line it shows, the default drawn behind an empty field included, has to sit inside
/// the field's frame. Lines are read from the pixels between the bar and a line's height below
/// the field, where nothing else is drawn on a new routine. Where
/// the `_` draws on a wrapped name is snapshot-tested.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class TitleWrappingUITests: XCTestCase {
    /// Three lines at AX5.
    private static let threeLines = "Hot beat drills and abs"

    static let largestTextSize = "UICTContentSizeCategoryAccessibilityXXXL"
    /// How far below the field the lines are read: more than a line of the title at AX5.
    private static let spill: CGFloat = 80

    @MainActor
    func testWrappedTitleAtLargestTextSize() throws {
        let app = XCUIApplication()
        // The workout's routine is seeded at this launch, and the title's checks run on a new
        // routine opened after it, so the test launches once.
        try workoutAtAX5(in: app)
        app.openNewRoutine()
        let title = app.routineTitle
        let keyboard = app.keyboards.element

        try XCTContext.runActivity(named: "The field covers the wrapped default") { _ in
            try assertLinesInsideField(title, lines: 2, "default at rest")
            title.tap()
            XCTAssertTrue(keyboard.appears())
            try assertLinesInsideField(title, lines: 2, "default, editing")
        }

        try XCTContext.runActivity(named: "The field covers a long name while editing") { _ in
            title.typeText(Self.threeLines)
            XCTAssertEqual(title.value(becoming: Self.threeLines), Self.threeLines)
            try assertLinesInsideField(title, lines: 3, "long name, editing")
        }
        XCTContext.runActivity(named: "A tap on line 2 puts the caret there") { _ in
            // "Hot beat" / "drills and" / "abs": a tap at the start of line 2 is before drills.
            let field = title.frame
            title.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 4, dy: field.height / 2)).tap()
            title.typeText("X")
            let moved = "Hot beat Xdrills and abs"
            XCTAssertEqual(title.value(becoming: moved), moved)
            title.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(title.value(becoming: Self.threeLines), Self.threeLines)
        }

        try XCTContext.runActivity(named: "The field covers a long name") { _ in
            returnLeavesEverythingInPlace(title, keyboard: keyboard)
            XCTAssertEqual(title.value as? String, Self.threeLines)
            try assertLinesInsideField(title, lines: 3, "long name at rest")
        }

        try XCTContext.runActivity(named: "A cleared name restores the wrapped default") { _ in
            title.tap()
            XCTAssertTrue(keyboard.appears())
            // The app moves the caret to the end after focus lands, which can come after keys
            // sent at once.
            let field = title.frame
            _ = try Ink.withCursor { try read(field) } until: { ink, cursor in
                ink.missAtEnd(cursor)
            }
            // Deleting from the end, not ⌘A: on Xcode Cloud, ⌘A sent here hid the keyboard and
            // selected nothing.
            let delete = XCUIKeyboardKey.delete.rawValue
            title.typeText(String(repeating: delete, count: Self.threeLines.count))
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            try assertLinesInsideField(title, lines: 2, "cleared, editing")
            returnLeavesEverythingInPlace(title, keyboard: keyboard)
            XCTAssertEqual(title.value as? String, "New routine")
            try assertLinesInsideField(title, lines: 2, "cleared, at rest")
        }

        try auditRowsAndPicker(in: app)
        assertLastRowClearsAddAtTheEnd(in: app, keyboard: keyboard)
        dragARowAtAX5(in: app)
        try supersetAtAX5(in: app)
        try drawerAtAX5(in: app)
    }

    /// The second row held and dragged above the first moves there at this size.
    @MainActor
    private func dragARowAtAX5(in app: XCUIApplication) {
        XCTContext.runActivity(named: "A row drags at the largest text size") { _ in
            let rows = app.exerciseRows
            let (first, last) = (rows.element(boundBy: 0), rows.element(boundBy: 1))
            // Its card's top, half the held row's height above the finger, clears the first
            // row's middle. Kept below the bar, where a release would put it back.
            let bar = app.navigationBars.firstMatch.frame.maxY
            let target = app.point(x: last.frame.midX, y: max(first.frame.midY, bar + 70))
            last.center.holdAndDrag(to: target)
            let moved = ["Dumbbell bench press", "Kneeling hip flexor stretch"]
            XCTAssertEqual(reading(app.exerciseNames, becoming: moved, within: 2), moved)
            attach(named: "reorder-ax5")
        }
    }

    /// The drawer, its places kept whole, and the Routines screen pass the audit at this size.
    @MainActor
    private func drawerAtAX5(in app: XCUIApplication) throws {
        try XCTContext.runActivity(named: "The drawer and the Routines screen at AX5") { _ in
            // Back from the routine pushed from Routines, to ++.
            app.buttons["BackButton"].tap()
            app.buttons["Menu"].tap()
            XCTAssertTrue(app.drawerTitle.appears(), "++ did not open the drawer")
            attach(named: "drawer-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            app.buttons["Routines"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Routines did not close the drawer")
            let row = app.buttons.matching(identifier: "routines.row").firstMatch
            XCTAssertTrue(row.appears(), "The routine isn't listed")
            attach(named: "routines-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
        }
    }

    /// Two rows joined by a node's drag at this size, and the audit with a superset on screen.
    @MainActor
    private func supersetAtAX5(in app: XCUIApplication) throws {
        let name = "A node joins two rows at AX5, and passes the audit"
        try XCTContext.runActivity(named: name) { _ in
            let rows = app.exerciseRows
            let (first, last) = (rows.element(boundBy: 0), rows.element(boundBy: 1))
            // The first row's middle is under the bar here, so the drag goes up from the last.
            let bar = app.navigationBars.firstMatch.frame.maxY
            last.nodePoint.holdAndDrag(to: app.point(x: 22, y: max(first.frame.midY, bar + 40)))
            XCTAssertEqual(app.supersets(becoming: "AA"), "AA")
            // Back at the top, as the rows' audit above was: the bar's small title, shown only
            // scrolled, doesn't scale, which the audit reports.
            app.scrollToTop(titled: app.routineTitle.value as? String ?? "")
            attach(named: "superset-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
        }
    }

    /// The audit, passing over what is in the navigation bar: the bar caps its text, End and
    /// the small title, at a size of its own, and shows the large content viewer on a long press
    /// instead. In a workout the list lands with the title under the bar, where its small copy
    /// shows cut short.
    /// Passed over as well, any text labeled one of `systemTexts`, such as a dialog's title,
    /// which the system caps the same way.
    @MainActor
    func auditBelowTheBar(in app: XCUIApplication, systemTexts: [String] = []) throws {
        let bar = app.navigationBars.firstMatch.frame
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            guard let element = issue.element else { return false }
            return bar.contains(element.frame) || systemTexts.contains(element.label)
        }
    }

    /// Rows, a row's sheet with a stepper open, and the picker, with results and narrowed down
    /// to its one Create row, pass the audit at this text size.
    @MainActor
    private func auditRowsAndPicker(in app: XCUIApplication) throws {
        let name = "A sheet and the picker at AX5 pass the audit"
        try XCTContext.runActivity(named: name) { _ in
            app.addExercise("Kneeling hip flexor stretch", searching: "kneel")
            XCTAssertTrue(app.buttons["Start"].appears())
            attach(named: "rail-ax5")
            // The rows are audited at AX5 later, once a node has joined two.
            app.exerciseRows.firstMatch.tap()
            let time = app.buttons["Time"]
            XCTAssertTrue(time.appears(), "Tapping a row opened no sheet")
            // Expanded before the row opens: in a sheet below its large height, a grown one
            // included, the audit reports the open row's value as clipped, though it draws in
            // full. Opened first, the row grows the sheet, and a tap on the grabber after it
            // races the growth, or takes the grown sheet back to half.
            attach(named: "sheet-ax5")
            let grabber = app.buttons["Sheet Grabber"]
            grabber.tap()
            XCTAssertEqual(grabber.value(becoming: "Expanded"), "Expanded")
            time.tap()
            XCTAssertTrue(app.buttons["Increase"].appears(), "Tapping Time opened no stepper")
            attach(named: "sheet-expanded-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            app.buttons["Close"].tap()
            XCTAssertTrue(time.disappears(), "Close left the sheet up")
            _ = app.openPicker()
            attach(named: "picker-ax5")
            app.search(for: "curl")
            XCTAssertTrue(app.pickerRows["Biceps curl, Dumbbells"].appears())
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            app.searchForNothing(replacing: "curl")
            attach(named: "picker-create-only-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            try auditNewExerciseForm(in: app)
        }
    }

    /// New exercise passes the audit at this text size, where the name wraps under its label;
    /// Cancel then leaves the picker as the next check expects it. No cheaper tier reaches the
    /// form: it is the app's, composed of system rows on the sheet's stack. Its checklists are
    /// not audited here, to keep the UI tests in their budget.
    @MainActor
    private func auditNewExerciseForm(in app: XCUIApplication) throws {
        let create = app.buttons["picker.create"]
        XCTAssertTrue(create.settles(), "Create is still moving")
        create.tap()
        let name = app.descendants(matching: .any)["newExercise.name"]
        XCTAssertTrue(name.appears(), "Create opened no form")
        XCTAssertEqual(name.value as? String, "zzz")
        attach(named: "new-exercise-form-ax5")
        // Cancel and Add are the bar's, which caps its text as it does End.
        try auditBelowTheBar(in: app, systemTexts: ["Cancel", "Add"])
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.searchField.appears(), "Cancel did not come back to the search")
    }

    /// At this size the second row goes in under Add exercise's +, so an add has to scroll to
    /// the end of the list, where the last row clears the + with the screen's spacing to spare.
    @MainActor
    private func assertLastRowClearsAddAtTheEnd(in app: XCUIApplication, keyboard: XCUIElement) {
        let name = "At the end of a long list, the last row clears Add exercise's +"
        XCTContext.runActivity(named: name) { _ in
            // The open search's field covers Close, out of VoiceOver's reach, until its X ends
            // the search; Close then closes the sheet.
            let close = app.buttons["Close"]
            XCTAssertFalse(close.exists, "VoiceOver reaches Close under the open search")
            app.tapSearchButton()
            XCTAssertTrue(keyboard.disappears(), "The search's X left the keyboard up")
            XCTAssertTrue(close.appears(), "The search's X did not uncover Close")
            close.tap()
            XCTAssertTrue(app.searchButton.disappears(), "Close left the picker up")
            app.addExercise("Dumbbell bench press, Dumbbells, bench", searching: "dumbbellb")
            XCTAssertTrue(app.lastRowClearsAddExercise(), "The add left the row under the +")
            attach(named: "rail-after-add-ax5")
            // The last row: the first, its plan making it taller, has its middle under the bar.
            app.lastExerciseRow.swipeOpen()
            XCTAssertTrue(app.buttons["Remove"].appears(), "A swipe did not open the row")
            app.swipeUp()
            XCTAssertTrue(app.buttons["Remove"].disappears(), "A scroll left the row open")
            app.swipeUp()
            XCTAssertTrue(app.buttons["Start"].appears())
            attach(named: "rail-end-ax5")
            // 16pt, the screen's spacing, give or take rounding.
            XCTAssertGreaterThanOrEqual(
                app.buttons["Add exercise"].frame.minY - app.lastExerciseRow.frame.maxY,
                15.5,
                "The last row does not clear the + with room to spare",
            )
        }
    }

    /// Return ends the edit, and the title stays where it was: only the keyboard moves.
    @MainActor
    private func returnLeavesEverythingInPlace(
        _ title: XCUIElement,
        keyboard: XCUIElement,
        line: UInt = #line,
    ) {
        let before = [title.frame]
        title.typeText("\n")
        XCTAssertTrue(keyboard.disappears(), "Return did not end the edit", line: line)
        XCTAssertEqual(
            watchFrames(of: [title], for: RenameUITests.keyboardAvoidanceWindow),
            before,
            "Ending the edit moved the title",
            line: line,
        )
    }

    /// Every line of text read around the field lies inside it.
    @MainActor
    private func assertLinesInsideField(
        _ title: XCUIElement,
        lines expected: Int,
        _ label: String,
        line: UInt = #line,
    ) throws {
        let field = title.frame
        // The value can change a frame before the lines are drawn.
        let drawn = Date.now.addingTimeInterval(2)
        var ink = try read(field)
        while ink.lines.count != expected, Date.now < drawn {
            ink = try read(field)
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
    }

    /// The ink in the field's column, from just under the bar down to `spill` below the field,
    /// far enough to take in a line drawn past its bottom. The strip starts above the field, on
    /// plain background.
    @MainActor
    private func read(_ field: CGRect) throws -> Ink {
        let top = field.minY - 16
        let bottom = field.maxY + Self.spill
        let strip = CGRect(x: field.minX, y: top, width: field.width, height: bottom - top)
        return try TitleShot().ink(in: strip, background: strip.origin)
    }
}

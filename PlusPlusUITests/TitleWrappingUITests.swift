import XCTest

/// The title at the largest accessibility text size, where it wraps. VoiceOver frames the field,
/// so every line it shows, the default drawn behind an empty field included, has to sit inside
/// the field's frame, and the drawn `_` has to stay under the line the caret is on. Lines and the
/// `_` are read from the pixels between the bar and "Add exercise".
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class TitleWrappingUITests: XCTestCase {
    /// Two lines at AX5: "Arm and" over "back".
    private static let twoLines = "Arm and back"
    /// Three lines at AX5, with no descenders, so a thin run of ink can only be the `_`.
    private static let threeLines = "Hot beat drills and abs"

    @MainActor
    func testWrappedTitleAtLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.appears(within: 10))
        let keyboard = app.keyboards.element

        try XCTContext.runActivity(named: "The field covers the wrapped default") { _ in
            try assertLinesInsideField(title, in: app, lines: 2, "default at rest")
            title.tap()
            XCTAssertTrue(keyboard.appears())
            try assertLinesInsideField(title, in: app, lines: 2, "default, editing")
        }

        try XCTContext.runActivity(named: "The _ draws under line 2") { _ in
            title.typeText(Self.twoLines)
            try assertCursorUnder(line: 1, of: 2, title, in: app, "end of a two-line name")
            title.typeKey(.leftArrow, modifierFlags: [])
            title.typeKey(.leftArrow, modifierFlags: [])
            try assertCursorUnder(line: 1, of: 2, title, in: app, "inside line 2 of two")

            // Typing over everything leaves the caret at the end of the three lines. Two words
            // back is before "and", inside the middle line.
            title.typeKey("a", modifierFlags: .command)
            title.typeText(Self.threeLines)
            try assertLinesInsideField(title, in: app, lines: 3, "long name, editing")
            title.typeKey(.leftArrow, modifierFlags: .option)
            title.typeKey(.leftArrow, modifierFlags: .option)
            try assertCursorUnder(line: 1, of: 3, title, in: app, "inside line 2 of three")
        }

        try XCTContext.runActivity(named: "The field covers a long name") { _ in
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
            XCTAssertEqual(title.value as? String, Self.threeLines)
            try assertLinesInsideField(title, in: app, lines: 3, "long name at rest")
        }

        try XCTContext.runActivity(named: "A cleared name restores the wrapped default") { _ in
            title.tap()
            XCTAssertTrue(keyboard.appears())
            title.typeKey("a", modifierFlags: .command)
            title.typeText(XCUIKeyboardKey.delete.rawValue)
            try assertLinesInsideField(title, in: app, lines: 2, "cleared, editing")
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
            XCTAssertEqual(title.value as? String, "New routine")
            try assertLinesInsideField(title, in: app, lines: 2, "cleared, at rest")
        }
    }

    /// Every line of text between the bar and "Add exercise" lies inside the field.
    @MainActor
    private func assertLinesInsideField(
        _ title: XCUIElement,
        in app: XCUIApplication,
        lines expected: Int,
        _ label: String,
        line: UInt = #line,
    ) throws {
        let ink = try read(title, in: app, label)
        let frame = title.frame
        XCTAssertEqual(ink.lines.count, expected, "\(label): line count", line: line)
        for (index, text) in ink.lines.enumerated() {
            XCTAssertGreaterThanOrEqual(
                text.points.lowerBound,
                frame.minY - 1,
                "\(label): line \(index + 1) starts above the field \(frame)",
                line: line,
            )
            XCTAssertLessThanOrEqual(
                text.points.upperBound,
                frame.maxY + 1,
                "\(label): line \(index + 1) ends below the field \(frame)",
                line: line,
            )
        }
        let button = app.buttons["Add exercise"].frame
        XCTAssertLessThanOrEqual(frame.maxY, button.minY, "\(label): field overlaps the button")
    }

    /// The `_` sits below the given line (zero-based): above the next line's glyphs, or, under
    /// the last line, less than a line's height below it. Where in the gap between two lines it
    /// sits is the maintainer's call, so this does not judge it.
    @MainActor
    private func assertCursorUnder(
        line target: Int,
        of count: Int,
        _ title: XCUIElement,
        in app: XCUIApplication,
        _ label: String,
        line: UInt = #line,
    ) throws {
        let found = try Ink.withCursor { try read(title, in: app, label, attach: false) }
        let ink = try XCTUnwrap(found, "\(label): no _ over two blink cycles", line: line)
        attach(ink.shot, label)
        XCTAssertEqual(ink.lines.count, count, "\(label): line count", line: line)
        let cursor = try XCTUnwrap(ink.cursor, line: line).points
        let above = ink.lines[target].points
        XCTAssertGreaterThan(cursor.lowerBound, above.upperBound, "\(label): _ not below")
        if target + 1 < ink.lines.count {
            let below = ink.lines[target + 1].points
            XCTAssertLessThan(cursor.upperBound, below.lowerBound, "\(label): _ hits next line")
        } else {
            // Below the last line by less than a line's height: under it, not a line further.
            XCTAssertLessThan(
                cursor.lowerBound - above.upperBound,
                above.upperBound - above.lowerBound,
                "\(label): _ hangs too far below the last line",
                line: line,
            )
        }
    }

    /// The ink in the field's column, from just under the bar down to "Add exercise". The strip
    /// starts above the field, on plain background.
    @MainActor
    private func read(
        _ title: XCUIElement,
        in app: XCUIApplication,
        _ label: String,
        attach shouldAttach: Bool = true,
    ) throws -> Ink {
        let shot = try TitleShot()
        if shouldAttach {
            attach(shot, label)
        }
        let field = title.frame
        let top = field.minY - 16
        let bottom = app.buttons["Add exercise"].frame.minY - 1
        let strip = CGRect(x: field.minX, y: top, width: field.width, height: bottom - top)
        return shot.ink(in: strip, background: strip.origin)
    }

    @MainActor
    private func attach(_ shot: TitleShot, _ label: String) {
        let attachment = XCTAttachment(screenshot: shot.screenshot)
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

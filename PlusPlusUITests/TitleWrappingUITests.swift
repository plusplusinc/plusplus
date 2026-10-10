import XCTest

/// The title at the largest accessibility text size, where it wraps. VoiceOver frames the field,
/// so every line it shows, the default drawn behind an empty field included, has to sit inside
/// the field's frame, and the drawn `_` has to stay under the line the caret is on. Lines and the
/// `_` are read from the pixels between the bar and "Add exercise".
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class TitleWrappingUITests: XCTestCase {
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
        let addExercise = app.buttons["Add exercise"]
        let keyboard = app.keyboards.element

        try XCTContext.runActivity(named: "The field covers the wrapped default") { _ in
            try assertLinesInsideField(title, above: addExercise, lines: 2, "default at rest")
            title.tap()
            XCTAssertTrue(keyboard.appears())
            try assertLinesInsideField(title, above: addExercise, lines: 2, "default, editing")
        }

        try XCTContext.runActivity(named: "The _ draws under line 2") { _ in
            // "Arm and" over "back".
            title.typeText("Arm and back")
            XCTAssertEqual(title.value(becoming: "Arm and back"), "Arm and back")
            try assertCursorUnder(
                line: 1,
                of: 2,
                title,
                above: addExercise,
                "end of a two-line name",
            )
            // typeText would type an arrow's raw value as a character.
            title.typeKey(.leftArrow, modifierFlags: [])
            title.typeKey(.leftArrow, modifierFlags: [])
            try assertCursorUnder(line: 1, of: 2, title, above: addExercise, "inside line 2 of two")

            // Typing over everything leaves the caret at the end of the three lines. Two words
            // back is before "and", inside the middle line.
            title.typeKey("a", modifierFlags: .command)
            title.typeText(Self.threeLines)
            XCTAssertEqual(title.value(becoming: Self.threeLines), Self.threeLines)
            try assertLinesInsideField(title, above: addExercise, lines: 3, "long name, editing")
            title.typeKey(.leftArrow, modifierFlags: .option)
            title.typeKey(.leftArrow, modifierFlags: .option)
            try assertCursorUnder(
                line: 1,
                of: 3,
                title,
                above: addExercise,
                "inside line 2 of three",
            )
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
            title.typeKey("a", modifierFlags: .command)
            title.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            try assertLinesInsideField(title, above: addExercise, lines: 2, "cleared, editing")
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
            XCTAssertEqual(title.value as? String, "New routine")
            try assertLinesInsideField(title, above: addExercise, lines: 2, "cleared, at rest")
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
        attach(ink.shot, named: label)
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

    /// The `_` sits below the given line (zero-based): above the next line's glyphs, or, under
    /// the last line, less than a line's height below it. Where in the gap between two lines it
    /// sits is the maintainer's call, so this does not judge it.
    /// It waits for that, since keys typed before it may not have been handled yet. Only the line
    /// is checked, so a read from before the arrows inside line 2 of two passes too.
    @MainActor
    private func assertCursorUnder(
        line target: Int,
        of count: Int,
        _ title: XCUIElement,
        above addExercise: XCUIElement,
        _ label: String,
        line: UInt = #line,
    ) throws {
        let field = title.frame
        let button = addExercise.frame
        let ink = try Ink.withCursor(line: line) { try read(field, above: button) } until: {
            Self.miss($1, under: target, of: count, in: $0).map { "\(label): \($0)" }
        }
        attach(ink.shot, named: label)
        XCTAssertEqual(title.frame, field, "\(label): the field moved while read", line: line)
    }

    /// What is wrong with the `_` for it to sit under line `target` of `count`, or nil.
    private static func miss(
        _ cursor: Ink.Run,
        under target: Int,
        of count: Int,
        in ink: Ink,
    ) -> String? {
        guard ink.lines.count == count else { return "\(ink.lines.count) lines, not \(count)" }
        let (cursor, above) = (cursor.points, ink.lines[target].points)
        if cursor.lowerBound <= above.upperBound {
            return "_ not below: \(cursor) under \(above)"
        }
        if target + 1 < count {
            let below = ink.lines[target + 1].points
            return cursor.upperBound < below.lowerBound ? nil : "_ hits next line: \(cursor), \(below)"
        }
        // Below the last line by less than a line's height: under it, not a line further.
        let height = above.upperBound - above.lowerBound
        return cursor.lowerBound - above.upperBound < height ? nil : "_ hangs too far below the last line"
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

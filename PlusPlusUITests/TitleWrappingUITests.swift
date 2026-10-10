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

        try XCTContext.runActivity(named: "Rows and the picker at AX5 pass the audit") { _ in
            app.addExercise("Kneeling hip flexor stretch", searching: "kneeling")
            XCTAssertTrue(app.buttons["Start"].appears())
            attach(named: "rail-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            addExercise.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.appears())
            attach(named: "picker-ax5")
            // Audited in use: at rest, the system search bar reports that it cannot scale, with
            // no element named, though it draws at this size, as the screenshot shows.
            search.tap()
            search.typeText("curl")
            XCTAssertTrue(app.pickerRows["Biceps curl, Dumbbells"].appears())
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "zzz")
            XCTAssertTrue(app.staticTexts["No Results for \u{201C}zzz\u{201D}"].appears())
            attach(named: "picker-no-results-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
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

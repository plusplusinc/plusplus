import XCTest

/// Renaming through the real keyboard and text system at the default text size. The rules are
/// unit-tested in the package and the resting look is snapshot-tested; this checks what needs
/// key presses, taps, the caret UIKit places, and focus: where the `_` draws while editing, that
/// the title stays put as the keyboard rises, and that Return keeps the name. The `_` is drawn,
/// not an element, so it is read from the pixels of the field and a strip below it.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class RenameUITests: XCTestCase {
    /// UIKit scrolls the focused field once the keyboard has risen, about 0.8s after the tap,
    /// while the keyboard's element reports its final frame from the start. Whether the title
    /// moved shows only by watching it for longer than that.
    private static let keyboardAvoidanceWindow: TimeInterval = 2

    @MainActor
    func testRenameAtDefaultSize() throws {
        let app = XCUIApplication()
        // The simulator keeps the last text size it was set to, so the default is pinned.
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTFail("Deliberate failure to time Xcode Cloud's red run (throwaway, never merged)")
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.appears(within: 10))
        let addExercise = app.buttons["Add exercise"]
        let keyboard = app.keyboards.element
        let field = title.frame
        let button = addExercise.frame

        try startEditing(title, keyboard: keyboard, addExercise: addExercise, at: (field, button))

        // No descenders, so a thin run of ink under the line can only be the `_`.
        title.typeText("Arm back")
        XCTAssertEqual(title.value(becoming: "Arm back"), "Arm back")
        XCTContext.runActivity(named: "A one-line name keeps a one-line field") { _ in
            XCTAssertEqual(title.frame, field, "A one-line name resized the field")
            XCTAssertEqual(addExercise.frame, button)
        }
        let afterTyping = try XCTContext.runActivity(named: "Typing in the middle") { _ in
            try typeInTheMiddle(of: title, in: field)
        }
        let tapped = try XCTContext.runActivity(named: "A tap puts the _ under its word") { _ in
            try tapStartOfAnd(in: title, at: field, after: afterTyping)
        }
        try XCTContext.runActivity(named: "A range hides the _") { _ in
            try assertRangeHidesCursor(in: title, at: field, from: tapped)
        }

        XCTContext.runActivity(named: "Return ends editing and keeps the name") { _ in
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears(), "Return should end editing")
            XCTAssertEqual(title.value as? String, "Arm and back")
        }
        XCTContext.runActivity(named: "Editing a name starts at its end") { _ in
            title.tap()
            title.typeText(" day")
            XCTAssertEqual(title.value(becoming: "Arm and back day"), "Arm and back day")
        }
        try XCTContext.runActivity(named: "The _ clears descenders") { _ in
            try assertCursorClearsDescenders(in: title, field: field)
        }
    }

    /// Taps the default title: it has to stay put, by frame and by pixel, as the keyboard rises,
    /// turn gray with the `_` under its first letter, and show the background at the keyboard's
    /// corners.
    @MainActor
    private func startEditing(
        _ title: XCUIElement,
        keyboard: XCUIElement,
        addExercise: XCUIElement,
        at frames: (field: CGRect, button: CGRect),
    ) throws {
        let (field, button) = frames
        let atRest = try read(field)
        let restText = try XCTUnwrap(atRest.lines.first)
        XCTContext.runActivity(named: "The default's line is inside the field at rest") { _ in
            // The strip starts at the field's top, so ink in its first row may be cut off.
            XCTAssertGreaterThan(restText.rows.lowerBound, 0, "The line starts above the field")
            XCTAssertLessThanOrEqual(restText.points.upperBound, field.maxY + 1, "It ends below")
        }
        title.tap()
        XCTAssertTrue(keyboard.appears())

        XCTContext.runActivity(named: "Editing starts in place") { _ in
            let deadline = Date.now.addingTimeInterval(Self.keyboardAvoidanceWindow)
            var frames = (title.frame, addExercise.frame)
            while Date.now < deadline, frames == (field, button) {
                frames = (title.frame, addExercise.frame)
            }
            XCTAssertEqual(frames.0, field, "The title's frame moved")
            XCTAssertEqual(frames.1, button, "Add exercise moved")
        }
        let placeholder = try Ink.withCursor { try read(field) }
        let placeholderText = try XCTUnwrap(placeholder.lines.first)
        XCTContext.runActivity(named: "The title's pixels stay put") { _ in
            XCTAssertEqual(placeholderText.columns, restText.columns, "The title moved sideways")
            XCTAssertEqual(
                placeholderText.points.lowerBound,
                restText.points.lowerBound,
                "The title moved down",
            )
        }
        try XCTContext.runActivity(named: "The default turns gray, with the _ under its N") { _ in
            let rest = try XCTUnwrap(atRest.brightestInk(in: restText.rows))
            let editing = try XCTUnwrap(placeholder.brightestInk(in: placeholderText.rows))
            XCTAssertLessThan(editing, rest - 40, "The default name should turn gray")
            let cursor = try XCTUnwrap(placeholder.cursor).columns
            let letters = placeholderText.columns
            XCTAssertLessThan(abs(cursor.lowerBound - letters.lowerBound), 8, "_ not under N")
            XCTAssertLessThan(cursor.upperBound, letters.lowerBound + 40, "_ not under N")
        }
        try XCTContext.runActivity(named: "The background shows at the keyboard's corners") { _ in
            try assertNoBandAtCorners(of: keyboard, in: placeholder.shot)
        }
    }

    /// In "Arm back", a word back puts the `_` inside the name, and typing there edits the
    /// middle: "Arm and back".
    @MainActor
    private func typeInTheMiddle(of title: XCUIElement, in field: CGRect) throws -> Ink {
        title.typeKey(.leftArrow, modifierFlags: .option)
        let beforeBack = try Ink.withCursor { try read(field) } until: { ink, cursor in
            Self.miss(cursor, inside: ink)
        }
        let cell = try Double(XCTUnwrap(beforeBack.lines.first).columns.count) / 8

        title.typeText("and  " + XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(title.value(becoming: "Arm and back"), "Arm and back")
        // Twelve cells wide, so the shot is of "Arm and back" and not a frame of it half drawn,
        // with the `_` moved on to the b, inside the name.
        return try Ink.withCursor { try read(field) } until: { ink, cursor in
            guard let name = ink.lines.first else { return "No line over the _" }
            let wide = Double(name.columns.count) / cell
            guard abs(wide - 12) < 0.5 else { return "The name is \(wide) cells wide, not 12" }
            return Self.miss(cursor, under: name.cell(8, of: 12), "the b of back")
        }
    }

    /// Taps the start of "and" in "Arm and back" and checks that the `_` moved under it.
    @MainActor
    private func tapStartOfAnd(
        in title: XCUIElement,
        at field: CGRect,
        after afterTyping: Ink,
    ) throws -> Ink {
        let and = try XCTUnwrap(afterTyping.lines.first).cell(4, of: 12)
        let point = (and.start + 0.2 * and.width) / afterTyping.shot.scale
        title.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point, dy: field.height / 2))
            .tap()
        return try Ink.withCursor { try read(field) } until: { _, cursor in
            Self.miss(cursor, under: and, "the a of and")
        }
    }

    /// Selects a word and checks that no `_` shows while the highlight does, then collapses the
    /// selection and checks that the `_` is back.
    @MainActor
    private func assertRangeHidesCursor(
        in title: XCUIElement,
        at field: CGRect,
        from tapped: Ink,
    ) throws {
        let line = try XCTUnwrap(tapped.lines.first).rows
        let unselected = tapped.differingPixels(in: line)
        title.typeKey(.rightArrow, modifierFlags: [.shift, .option])
        // The highlight fills the selected cells' background, so far more of the line differs
        // from the screen background than the glyphs alone. Until it shows, the key may not
        // have been handled, and the `_` may still be lit.
        let highlight = unselected + 2000
        let shown = Date.now.addingTimeInterval(Ink.twoBlinks)
        var selected = try read(field)
        while selected.differingPixels(in: line) <= highlight, Date.now < shown {
            selected = try read(field)
        }
        XCTAssertGreaterThan(
            selected.differingPixels(in: line),
            highlight,
            "No selection highlight",
        )
        // A `_` that is there shows within one full blink cycle.
        let deadline = Date.now.addingTimeInterval(Ink.twoBlinks / 2)
        while Date.now < deadline {
            XCTAssertNil(try read(field).cursor, "A range selection should not show the _")
        }

        title.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertNoThrow(try Ink.withCursor { try read(field) }, "A collapsed range shows no _")
    }

    /// Under the "y" of "gym yoga", the `_` is a band of its own, below the y's tail.
    @MainActor
    private func assertCursorClearsDescenders(in title: XCUIElement, field: CGRect) throws {
        title.typeKey("a", modifierFlags: .command)
        title.typeText("gym yoga")
        XCTAssertEqual(title.value(becoming: "gym yoga"), "gym yoga")
        title.typeKey(.leftArrow, modifierFlags: .option)
        // A `_` merged into the y's tail is no thin run, so it never counts as under the y.
        _ = try Ink.withCursor { try read(field) } until: { ink, cursor in
            guard let name = ink.lines.first else { return "No line over the _" }
            return Self.miss(cursor, under: name.cell(4, of: 8), "the y of yoga")
        }
    }

    /// No hard edge or band at the keyboard's top corners: just outside its rounded glass, the
    /// screen's own background shows. The shot is taken once the keyboard has risen.
    @MainActor
    private func assertNoBandAtCorners(of keyboard: XCUIElement, in shot: TitleShot) throws {
        attach(shot, named: "keyboard-corners")
        let frame = keyboard.frame
        let background = try shot.color(at: CGPoint(x: 200, y: frame.minY - 60))
        // Rows just above the keyboard and the corners just inside its frame's top edge.
        let samples = [
            CGPoint(x: 4, y: frame.minY - 2),
            CGPoint(x: 200, y: frame.minY - 2),
            CGPoint(x: 398, y: frame.minY - 2),
            CGPoint(x: frame.minX + 2, y: frame.minY + 2),
            CGPoint(x: frame.maxX - 2, y: frame.minY + 2),
        ]
        for sample in samples {
            let color = try shot.color(at: sample)
            let distance = TitleShot.distance(color, background)
            XCTAssertLessThan(distance, 24, "A band at \(sample): \(color) vs \(background)")
        }
    }

    /// What is wrong with a `_` that should be inside its line, before the last letter's edge
    /// and after the first's, or nil.
    private static func miss(_ cursor: Ink.Run, inside ink: Ink) -> String? {
        guard let letters = ink.lines.first?.columns else { return "No line over the _" }
        if cursor.columns.upperBound >= letters.upperBound {
            return "The _ should leave the end: it spans \(cursor.columns), the name at \(letters)"
        }
        if cursor.columns.lowerBound <= letters.lowerBound {
            return "The _ should be inside: it spans \(cursor.columns), the name at \(letters)"
        }
        return nil
    }

    /// What is wrong with a `_` that should start under a character's cell, or nil.
    private static func miss(
        _ cursor: Ink.Run,
        under cell: (start: Double, width: Double),
        _ name: String,
    ) -> String? {
        let off = abs(Double(cursor.columns.lowerBound) - cell.start)
        return off < cell.width / 2 ? nil : "The _ should sit under \(name): \(off) columns off"
    }

    /// The ink in the field and a strip below it for the `_`, short of the next view, against
    /// the field's far right, which is past any short name.
    @MainActor
    private func read(_ field: CGRect) throws -> Ink {
        let strip = CGRect(
            x: field.minX,
            y: field.minY,
            width: field.width,
            height: field.height + 12,
        )
        return try TitleShot().ink(in: strip, background: CGPoint(x: field.maxX - 1, y: field.minY))
    }
}

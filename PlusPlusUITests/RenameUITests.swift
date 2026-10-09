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
        app.launch()
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.appears(within: 10))
        let addExercise = app.buttons["Add exercise"]
        let keyboard = app.keyboards.element
        let field = title.frame
        let button = addExercise.frame

        try startEditing(title, keyboard: keyboard, addExercise: addExercise)

        // No descenders, so a thin run of ink under the line can only be the `_`.
        title.typeText("Arm back")
        XCTContext.runActivity(named: "A one-line name keeps a one-line field") { _ in
            XCTAssertEqual(title.frame, field, "A one-line name resized the field")
            XCTAssertEqual(addExercise.frame, button)
        }
        let afterTyping = try XCTContext.runActivity(named: "Typing in the middle") { _ in
            try typeInTheMiddle(of: title, in: field)
        }
        let tapped = try XCTContext.runActivity(named: "A tap puts the _ under its word") { _ in
            try tapStartOfAnd(in: title, after: afterTyping)
        }
        try XCTContext.runActivity(named: "A range hides the _") { _ in
            try assertRangeHidesCursor(in: title, from: tapped)
        }

        XCTContext.runActivity(named: "Return ends editing and keeps the name") { _ in
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears(), "Return should end editing")
            XCTAssertEqual(title.value as? String, "Arm and back")
        }
        XCTContext.runActivity(named: "Editing a name starts at its end") { _ in
            title.tap()
            title.typeText(" day")
            XCTAssertEqual(title.value as? String, "Arm and back day")
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
    ) throws {
        let field = title.frame
        let button = addExercise.frame
        let atRest = try read(field)
        let restText = try XCTUnwrap(atRest.lines.first)
        let tapped = Date.now
        title.tap()
        XCTAssertTrue(keyboard.appears())

        XCTContext.runActivity(named: "Editing starts in place") { _ in
            let deadline = tapped.addingTimeInterval(Self.keyboardAvoidanceWindow)
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
        XCTContext.runActivity(named: "The background shows at the keyboard's corners") { _ in
            assertNoBandAtCorners(of: keyboard, in: placeholder.shot)
        }
    }

    /// In "Arm back", a word back puts the `_` inside the name, and typing there edits the
    /// middle: "Arm and back".
    @MainActor
    private func typeInTheMiddle(of title: XCUIElement, in field: CGRect) throws -> Ink {
        let atEnd = try XCTUnwrap(Ink.withCursor { try read(field) }.cursor).columns
        title.typeKey(.leftArrow, modifierFlags: .option)
        let beforeBack = try Ink.withCursor(awayFrom: atEnd) { try read(field) }
        let cursor = try XCTUnwrap(beforeBack.cursor).columns
        let letters = try XCTUnwrap(beforeBack.lines.first).columns
        XCTAssertLessThan(cursor.upperBound, atEnd.lowerBound, "The _ should leave the end")
        XCTAssertGreaterThan(cursor.lowerBound, letters.lowerBound, "The _ should be inside")

        title.typeText("and  " + XCUIKeyboardKey.delete.rawValue)
        let typed = try Ink.withCursor(awayFrom: cursor) { try read(field) }
        let moved = try XCTUnwrap(typed.cursor).columns
        let longer = try XCTUnwrap(typed.lines.first).columns
        XCTAssertGreaterThan(moved.lowerBound, cursor.lowerBound, "The _ should move on")
        XCTAssertLessThan(moved.upperBound, longer.upperBound, "The _ should stay inside")
        return typed
    }

    /// Taps the start of "and" in "Arm and back" and checks that the `_` moved under it.
    @MainActor
    private func tapStartOfAnd(in title: XCUIElement, after afterTyping: Ink) throws -> Ink {
        let and = try XCTUnwrap(afterTyping.lines.first).cell(4, of: 12)
        let point = (and.start + 0.2 * and.width) / afterTyping.shot.scale
        let field = title.frame
        title.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point, dy: field.height / 2))
            .tap()
        let moved = try Ink.withCursor(awayFrom: afterTyping.cursor?.columns) { try read(field) }
        let cursor = try XCTUnwrap(moved.cursor).columns
        XCTAssertLessThan(
            abs(Double(cursor.lowerBound) - and.start),
            and.width / 2,
            "The _ should sit under the a of and",
        )
        return moved
    }

    /// Selects a word and checks that no `_` shows while the highlight does, then collapses the
    /// selection and checks that the `_` is back.
    @MainActor
    private func assertRangeHidesCursor(in title: XCUIElement, from tapped: Ink) throws {
        let field = title.frame
        let line = try XCTUnwrap(tapped.lines.first).rows
        let unselected = tapped.differingPixels(in: line)
        title.typeKey(.rightArrow, modifierFlags: [.shift, .option])
        // A `_` that is there shows within one full blink cycle.
        let deadline = Date.now.addingTimeInterval(Ink.twoBlinks / 2)
        var selected = tapped
        while Date.now < deadline {
            selected = try read(field)
            XCTAssertNil(selected.cursor, "A range selection should not show the _")
        }
        // The highlight fills the selected cells' background, so far more of the line
        // differs from the screen background than the glyphs alone.
        let highlighted = selected.differingPixels(in: line)
        XCTAssertGreaterThan(highlighted, unselected + 2000, "No selection highlight")

        title.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertNoThrow(try Ink.withCursor { try read(field) }, "A collapsed range shows no _")
    }

    /// Under the "y" of "gym yoga", the `_` is a band of its own, below the y's tail.
    @MainActor
    private func assertCursorClearsDescenders(in title: XCUIElement, field: CGRect) throws {
        title.typeKey("a", modifierFlags: .command)
        title.typeText("gym yoga")
        let atEnd = try XCTUnwrap(Ink.withCursor { try read(field) }.cursor).columns
        title.typeKey(.leftArrow, modifierFlags: .option)
        // Throws when the `_` merges into the y's tail, since then there is no thin run.
        let underY = try Ink.withCursor(awayFrom: atEnd) { try read(field) }
        let cursor = try XCTUnwrap(underY.cursor).columns
        let y = try XCTUnwrap(underY.lines.first).cell(4, of: 8)
        XCTAssertLessThan(
            abs(Double(cursor.lowerBound) - y.start),
            y.width / 2,
            "The _ should sit under the y of yoga",
        )
    }

    /// No hard edge or band at the keyboard's top corners: just outside its rounded glass, the
    /// screen's own background shows. The shot is taken once the keyboard has risen.
    @MainActor
    private func assertNoBandAtCorners(of keyboard: XCUIElement, in shot: TitleShot) {
        attach(shot, named: "keyboard-corners")
        let frame = keyboard.frame
        let background = shot.color(at: CGPoint(x: 200, y: frame.minY - 60))
        // Rows just above the keyboard and the corners just inside its frame's top edge.
        let samples = [
            CGPoint(x: 4, y: frame.minY - 2),
            CGPoint(x: 200, y: frame.minY - 2),
            CGPoint(x: 398, y: frame.minY - 2),
            CGPoint(x: frame.minX + 2, y: frame.minY + 2),
            CGPoint(x: frame.maxX - 2, y: frame.minY + 2),
        ]
        for sample in samples {
            let color = shot.color(at: sample)
            let distance = TitleShot.distance(color, background)
            XCTAssertLessThan(distance, 24, "A band at \(sample): \(color) vs \(background)")
        }
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

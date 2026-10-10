import XCTest

/// Renaming through the real keyboard and text system at the default text size. The rules are
/// unit-tested in the package, and how the title looks at rest and while editing, `_` included,
/// is snapshot-tested; this checks what needs key presses, taps, the caret UIKit places, and
/// focus: that the title stays put as the keyboard rises, that typing lands where arrows and taps
/// put the caret, that a range shows the highlight, and that Return keeps the name. Where the
/// caret is shows in where typing lands. One check reads the drawn `_` from the pixels of the
/// field and a strip below it: that the caret the text system moved reaches the `_`.
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
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.appears(within: 10))
        let addExercise = app.buttons["Add exercise"]
        let keyboard = app.keyboards.element
        let field = title.frame
        let button = addExercise.frame

        // The default's width at rest gives a character's.
        let defaultName = try XCTUnwrap(title.value as? String)
        let restText = try startEditing(
            title,
            keyboard: keyboard,
            addExercise: addExercise,
            at: (field, button),
        )

        // No descenders, so a thin run of ink under the line can only be the `_`.
        title.typeText("Arm back")
        XCTAssertEqual(title.value(becoming: "Arm back"), "Arm back")
        XCTContext.runActivity(named: "A one-line name keeps a one-line field") { _ in
            XCTAssertEqual(title.frame, field, "A one-line name resized the field")
            XCTAssertEqual(addExercise.frame, button)
        }
        let afterTyping = try XCTContext.runActivity(
            named: "The _ follows the caret the text system moved",
        ) { _ in
            let cell = Double(restText.columns.count) / Double(defaultName.count)
            return try typeInTheMiddle(of: title, in: field, cell: cell)
        }
        XCTContext.runActivity(named: "A tap places the caret at its word") { _ in
            tapStartOfAnd(in: title, at: field, after: afterTyping)
        }
        try XCTContext.runActivity(named: "A range shows the highlight") { _ in
            try assertRangeShowsHighlight(in: title, at: field, from: afterTyping)
        }

        XCTContext.runActivity(named: "Return ends editing and keeps the name") { _ in
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears(), "Return should end editing")
            XCTAssertEqual(title.value as? String, "Arm and back")
        }
        try XCTContext.runActivity(named: "Editing a name starts at its end") { _ in
            title.tap()
            // The app moves the caret to the end after focus lands, which can come after typing
            // sent at once.
            _ = try Ink.withCursor { try read(field) } until: { ink, cursor in
                ink.missAtEnd(cursor)
            }
            title.typeText(" day")
            XCTAssertEqual(title.value(becoming: "Arm and back day"), "Arm and back day")
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
        }
        addAndSearchExercises(in: app, keyboard: keyboard)
        deleteExercises(in: app)
    }

    /// The picker opens fast and without the keyboard, search narrows it, and a pick adds a row.
    @MainActor
    private func addAndSearchExercises(in app: XCUIApplication, keyboard: XCUIElement) {
        let search = app.searchFields.firstMatch
        XCTContext.runActivity(named: "Add exercise opens the picker") { _ in
            XCTAssertFalse(app.buttons["Start"].exists, "Start shows with no exercises")
            app.buttons["Add exercise"].tap()
            XCTAssertTrue(search.appears(within: 1), "The picker took over a second to open")
            XCTAssertFalse(keyboard.exists, "Search took focus when the picker opened")
            XCTAssertEqual(app.pickerRows.firstMatch.label, "Balance board hold, Balance board")
        }
        XCTContext.runActivity(named: "Search narrows and shows an empty state") { _ in
            search.tap()
            search.typeText("curl")
            let curls = ["Biceps curl, Dumbbells", "Hammer curl, Dumbbells"]
            XCTAssertTrue(app.pickerRows[curls[0]].appears())
            XCTAssertEqual(app.pickerRows.allElementsBoundByIndex.map(\.label), curls)
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "zzz")
            XCTAssertTrue(app.staticTexts["No Results for \u{201C}zzz\u{201D}"].appears())
            XCTAssertEqual(app.pickerRows.count, 0)
            attachScreen(named: "picker-no-results")
            // While searching, the first Close ends the search; the next closes the sheet.
            for _ in 0 ..< 2 where search.exists {
                app.buttons["Close"].firstMatch.tap()
                _ = keyboard.disappears()
            }
            XCTAssertTrue(search.disappears(), "Close left the picker open")
            XCTAssertEqual(app.exerciseRows.count, 0, "Closing the picker added an exercise")
        }
        XCTContext.runActivity(named: "Start appears with the first exercise") { _ in
            app.addExercise("Barbell bench press, Barbell, bench")
            XCTAssertTrue(app.buttons["Start"].appears())
            app.buttons["Start"].tap()
            XCTAssertEqual(app.exerciseCount(becoming: 1), 1)
            XCTAssertFalse(search.exists, "Start opened something")
        }
        XCTContext.runActivity(named: "Six adds in a row, one a duplicate") { _ in
            // Each is in the first screenful: one tap to open, one to pick.
            for label in [
                "Band pull-apart, Band",
                "Band pull-apart, Band",
                "Balance board hold, Balance board",
                "Barbell back squat, Barbell",
                "Biceps curl, Dumbbells",
            ] {
                app.addExercise(label)
            }
            app.addExercise("Push-up", searching: "push-up")
            XCTAssertEqual(app.exerciseCount(becoming: 7), 7)
            attachScreen(named: "seven-exercises")
        }
        XCTContext.runActivity(named: "Rows read as name and equipment") { _ in
            let labels = app.exerciseRows.allElementsBoundByIndex.map(\.label)
            XCTAssertEqual(labels, [
                "Barbell bench press, Barbell, bench",
                "Band pull-apart, Band",
                "Band pull-apart, Band",
                "Balance board hold, Balance board",
                "Barbell back squat, Barbell",
                "Biceps curl, Dumbbells",
                "Push-up",
            ])
        }
    }

    /// A slow drag opens a row's Delete key, a fling deletes outright, and with no rows left
    /// Start goes.
    @MainActor
    private func deleteExercises(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Swipe left deletes a row") { _ in
            let row = app.exerciseRows.element(boundBy: 1)
            let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            start.press(
                forDuration: 0.1,
                thenDragTo: start.withOffset(CGVector(dx: -100, dy: 0)),
                withVelocity: .slow,
                thenHoldForDuration: 0.1,
            )
            let delete = app.buttons["Delete"]
            XCTAssertTrue(delete.appears(), "A slow drag did not open the row")
            attachScreen(named: "row-open")
            delete.tap()
            XCTAssertEqual(app.exerciseCount(becoming: 6), 6)
            XCTAssertTrue(delete.disappears())

            app.exerciseRows.element(boundBy: 0).swipeLeft(velocity: .fast)
            XCTAssertEqual(app.exerciseCount(becoming: 5), 5, "A fling did not delete the row")
        }
        XCTContext.runActivity(named: "Deleting the last row takes Start away") { _ in
            for left in (0 ..< 5).reversed() {
                app.exerciseRows.element(boundBy: 0).swipeLeft(velocity: .fast)
                XCTAssertEqual(app.exerciseCount(becoming: left), left)
            }
            XCTAssertTrue(app.buttons["Start"].disappears(), "Start stayed with no exercises")
        }
    }

    /// Taps the default title: it has to stay put, by frame and by pixel, as the keyboard rises,
    /// and show the background at the keyboard's corners. Returns the default's line at rest.
    @MainActor
    private func startEditing(
        _ title: XCUIElement,
        keyboard: XCUIElement,
        addExercise: XCUIElement,
        at frames: (field: CGRect, button: CGRect),
    ) throws -> Ink.Run {
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
        // Read once the keyboard has risen and UIKit would have scrolled.
        let placeholder = try read(field)
        let placeholderText = try XCTUnwrap(placeholder.lines.first)
        XCTContext.runActivity(named: "The title's pixels stay put") { _ in
            XCTAssertEqual(placeholderText.columns, restText.columns, "The title moved sideways")
            XCTAssertEqual(
                placeholderText.points.lowerBound,
                restText.points.lowerBound,
                "The title moved down",
            )
        }
        try XCTContext.runActivity(named: "The background shows at the keyboard's corners") { _ in
            try assertNoBandAtCorners(of: keyboard, in: placeholder.shot)
        }
        return restText
    }

    /// In "Arm back", a word back and typing there edit the middle: "Arm and back", with the `_`
    /// under the b of back, where the text system left the caret. `cell` is a character's width
    /// in pixel columns.
    @MainActor
    private func typeInTheMiddle(
        of title: XCUIElement,
        in field: CGRect,
        cell: Double,
    ) throws -> Ink {
        title.typeKey(.leftArrow, modifierFlags: .option)
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

    /// Taps the start of "and" in "Arm and back": typing there lands before the a.
    @MainActor
    private func tapStartOfAnd(in title: XCUIElement, at field: CGRect, after afterTyping: Ink) {
        guard let name = afterTyping.lines.first else {
            return XCTFail("No line in the shot of \"Arm and back\"")
        }
        let and = name.cell(4, of: 12)
        let point = (and.start + 0.2 * and.width) / afterTyping.shot.scale
        title.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point, dy: field.height / 2))
            .tap()
        title.typeText("X")
        XCTAssertEqual(title.value(becoming: "Arm Xand back"), "Arm Xand back")
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(title.value(becoming: "Arm and back"), "Arm and back")
    }

    /// Selects "and" and checks that the system highlight shows, then collapses the selection,
    /// since Return over a range would replace it. Snapshots hold that no `_` draws with a range.
    @MainActor
    private func assertRangeShowsHighlight(
        in title: XCUIElement,
        at field: CGRect,
        from unselectedShot: Ink,
    ) throws {
        let line = try XCTUnwrap(unselectedShot.lines.first).rows
        let unselected = unselectedShot.differingPixels(in: line)
        title.typeKey(.rightArrow, modifierFlags: [.shift, .option])
        // The highlight fills the selected cells' background, so far more of the line differs
        // from the screen background than the glyphs alone. Until it shows, the key may not
        // have been handled.
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
        // Return over a range that has not collapsed yet would replace it.
        title.typeKey(.rightArrow, modifierFlags: [])
        let collapsed = Date.now.addingTimeInterval(Ink.twoBlinks)
        while selected.differingPixels(in: line) > highlight, Date.now < collapsed {
            selected = try read(field)
        }
        XCTAssertLessThanOrEqual(
            selected.differingPixels(in: line),
            highlight,
            "The range did not collapse",
        )
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

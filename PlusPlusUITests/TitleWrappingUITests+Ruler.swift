import XCTest

@MainActor
extension TitleWrappingUITests {
    /// A ruler opened in the scrolled sheet, after the audit has stepped the text size through
    /// every size and back, rests with its value, the stretch's minute, under its line, in the
    /// middle of the sheet, and its labels stay out of the accessibility tree, which a hosted
    /// ruler never showed them in. Hidden from VoiceOver, its labels are read from the
    /// pixels under its ticks: the label nearest the middle is the minute's. Where a value sits
    /// along the ticks is `RulerScaleTests`'; a ruler through a live text size change is
    /// `ValueRulerTextSizeTests`', and one opening after it was laid out shut
    /// `ValueRulerOpeningTests`'. This shows both hold in the running sheet. `row`, Time, is
    /// open on entry.
    func assertRulerRestsOnItsValue(in app: XCUIApplication, row: XCUIElement) throws {
        row.tap()
        XCTAssertTrue(app.buttons["Increase"].disappears(), "Tapping the open row left it open")
        XCTAssertTrue(row.settles(), "The row kept moving after it shut")
        let from = row.center
        from.press(
            forDuration: 0.05,
            thenDragTo: from.down(-130),
            withVelocity: XCUIGestureVelocity(200),
            thenHoldForDuration: 0.2,
        )
        XCTAssertTrue(row.settles(), "The sheet kept scrolling")
        row.tap()
        let increase = app.buttons["Increase"]
        XCTAssertTrue(increase.appears(), "Tapping Time opened no stepper")
        XCTAssertTrue(increase.settles(), "The row kept moving after it opened")
        // Read until two screenshots in a row agree, so the ruler has come to rest.
        var last: CGFloat?
        let label = reading(
            Self.labelNearestMiddle(under: increase, in: row.frame, of: app),
            until: { center in
                defer { last = center }
                guard let center, let last else { return false }
                return abs(last - center) < 0.5
            },
            within: 3,
        )
        attach(named: "ruler-at-rest-ax5")
        // The row steps the value for VoiceOver; the ruler's labels are decoration.
        let minute = app.staticTexts.matching(NSPredicate(format: "label == %@", "1m")).firstMatch
        XCTAssertFalse(minute.exists, "The ruler's labels are in the accessibility tree")
        XCTAssertEqual(
            try XCTUnwrap(label, "No ruler labels under the open row's keys"),
            app.frame.midX,
            accuracy: 2,
            "The ruler's line is off the value its row shows",
        )
    }

    /// The middle of the ruler label nearest the screen's middle, from a screenshot: the strip
    /// under the ruler's ticks, which hang below the open row's keys. A label's glyphs sit up
    /// to 14 pt apart in SF Mono at AX5 ("1m"), and labels 60 pt or more.
    private static func labelNearestMiddle(
        under keys: XCUIElement,
        in fill: CGRect,
        of app: XCUIApplication,
    ) -> CGFloat? {
        // The keys' room below them, then the tallest tick and the gap above its label; deep
        // enough to take every glyph of a label at AX5, short of the fill's end.
        let labelsTop = keys.frame.maxY + 16 + 24 + 4
        let strip = CGRect(x: fill.minX, y: labelsTop, width: fill.width, height: 36)
        guard let ink = try? TitleShot().ink(
            in: strip,
            background: CGPoint(x: fill.minX + 2, y: strip.midY),
        ) else { return nil }
        let middle = app.frame.midX
        let nearest = ink.columnRuns(from: fill.minX, gap: 20).min {
            abs(($0.lowerBound + $0.upperBound) / 2 - middle) <
                abs(($1.lowerBound + $1.upperBound) / 2 - middle)
        }
        return nearest.map { ($0.lowerBound + $0.upperBound) / 2 }
    }
}

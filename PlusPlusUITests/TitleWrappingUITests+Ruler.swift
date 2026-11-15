import XCTest

@MainActor
extension TitleWrappingUITests {
    /// A ruler opened in the scrolled sheet rests with its value, the stretch's minute, under its
    /// line, in the middle of the sheet. In the sheet at this size, scrolled, the scroll view
    /// moved a ruler on by half its width once it had laid out, which no hosted ruler showed and
    /// the unscrolled sheet didn't either: only this sheet in the running app does. Where a
    /// value sits along the ticks is `RulerScaleTests`'. `row`, Time, is open on entry.
    func assertRulerRestsOnItsValue(in app: XCUIApplication, row: XCUIElement) {
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
        let minute = app.staticTexts.matching(NSPredicate(format: "label == %@", "1m")).firstMatch
        XCTAssertTrue(minute.appears(), "The ruler shows no label for its value")
        // The row opens and the ruler lays out, twice at this size, before it rests.
        XCTAssertTrue(minute.settles(), "The ruler kept moving after its row opened")
        attach(named: "ruler-at-rest-ax5")
        XCTAssertEqual(
            minute.frame.midX,
            app.frame.midX,
            accuracy: 1,
            "The ruler's line is off the value its row shows",
        )
    }
}

import XCTest

/// Ending an edit of the title, run within `testRenameAtDefaultSize` once there are exercises,
/// so the equipment's capsules and the rows sit under the title: by Return, and by a touch
/// anywhere outside the title, which also does its own thing. Only the keyboard moves.
extension RenameUITests {
    @MainActor
    func endEditsWithoutMoving(in app: XCUIApplication, keyboard: XCUIElement) {
        let capsules = app.equipment
        XCTContext.runActivity(named: "Return leaves everything in place") { _ in
            endEditWithoutMoving(in: app, keyboard: keyboard) {
                app.routineTitle.typeText("\n")
            }
        }
        XCTContext.runActivity(named: "A tap on empty space ends the edit in place") { _ in
            endEditWithoutMoving(in: app, keyboard: keyboard) {
                // Past the capsules' widest line, where nothing takes a tap. The gap under them
                // is the first row's, whose tap reaches up into the spacing.
                capsules.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                    .withOffset(CGVector(dx: 20, dy: 0)).tap()
            }
            XCTAssertFalse(app.buttons["Sets"].exists, "The tap on empty space opened a row")
        }
        XCTContext.runActivity(named: "A tap on a row ends the edit and opens the row") { _ in
            let sets = app.buttons["Sets"]
            endEditWithoutMoving(in: app, keyboard: keyboard) {
                app.exerciseRows.firstMatch.tap()
                XCTAssertTrue(sets.appears(), "The tap ended the edit but opened no sheet")
            }
            app.buttons["Close"].tap()
            XCTAssertTrue(sets.disappears(), "Close left the sheet up")
        }
        XCTContext.runActivity(named: "A tap on Start ends the edit in place") { _ in
            endEditWithoutMoving(in: app, keyboard: keyboard) {
                app.buttons["Start"].tap()
            }
        }
    }

    /// Starts an edit with a tap on the title and ends it with `end`, then watches the title,
    /// the capsules, and the first row for as long as UIKit could take to move them: none may.
    @MainActor
    private func endEditWithoutMoving(
        in app: XCUIApplication,
        keyboard: XCUIElement,
        end: () -> Void,
    ) {
        let elements = [
            app.routineTitle,
            app.equipment,
            app.exerciseRows.firstMatch,
        ]
        // A scroll back to the top can still be easing in.
        XCTAssertTrue(app.routineTitle.settles(), "The title kept moving before the edit")
        let atRest = elements.map(\.frame)
        app.routineTitle.tap()
        XCTAssertTrue(keyboard.appears(), "A tap on the title did not start an edit")
        end()
        XCTAssertTrue(keyboard.disappears(), "The edit did not end")
        XCTAssertEqual(
            watchFrames(of: elements, for: Self.keyboardAvoidanceWindow),
            atRest,
            "The title, the capsules, or the first row moved",
        )
    }
}

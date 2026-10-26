import XCTest

/// Ending an edit of the title, run within `testRenameAtDefaultSize` once there are exercises,
/// so the equipment's capsules and the rows sit under the title: by a touch outside the title,
/// which also does its own thing. Only the keyboard moves. Return in place is the hosted
/// `EditableTitleFocusTests`'. A tap on Start or ++, and a node's hold, go through the same
/// end-on-touch hook as the touches here, and are left to use.
extension RenameUITests {
    @MainActor
    func endEditsWithoutMoving(in app: XCUIApplication, keyboard: XCUIElement) {
        let capsules = app.equipment
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
        endEditsByDragging(in: app, keyboard: keyboard)
    }

    /// A scroll and a row's hold each end the edit as they start, and still do their own thing.
    /// The row's drag is undone, so the checks after this start from the same rows.
    @MainActor
    private func endEditsByDragging(in app: XCUIApplication, keyboard: XCUIElement) {
        let rows = app.exerciseRows
        let row = { rows.element(boundBy: $0) }
        let height = row(1).frame.minY - row(0).frame.minY
        let startEdit = {
            XCTAssertTrue(app.routineTitle.settles(), "The title kept moving before the edit")
            app.routineTitle.tap()
            XCTAssertTrue(keyboard.appears(), "A tap on the title did not start an edit")
        }
        XCTContext.runActivity(named: "A scroll ends the edit and scrolls the list") { _ in
            startEdit()
            let top = row(0).frame.minY
            // Row 1, clear of Start riding above the keyboard, which covers row 3.
            row(1).center.press(
                forDuration: 0.05,
                thenDragTo: row(1).center.down(-200),
                withVelocity: .default,
                thenHoldForDuration: 0,
            )
            XCTAssertTrue(keyboard.disappears(), "The scroll did not end the edit")
            XCTAssertTrue(
                reading(row(0).frame.minY < top, becoming: true, within: 2),
                "The scroll that ended the edit didn't scroll the list",
            )
            app.scrollToTop(titled: "Arm and back day")
        }
        XCTContext.runActivity(named: "A row's hold ends the edit and drags the row") { _ in
            let names = app.exerciseNames
            startEdit()
            row(0).center.holdAndDrag(to: row(0).center.down(1.2 * height))
            XCTAssertTrue(keyboard.disappears(), "The row's hold did not end the edit")
            var moved = names
            moved.swapAt(0, 1)
            XCTAssertEqual(reading(app.exerciseNames, becoming: moved, within: 2), moved)
            row(1).center.holdAndDrag(to: row(1).center.down(-1.2 * height))
            XCTAssertEqual(reading(app.exerciseNames, becoming: names, within: 2), names)
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

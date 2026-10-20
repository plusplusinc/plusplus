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
        XCTContext.runActivity(named: "A tap on ++ ends the edit and opens the drawer") { _ in
            XCTAssertTrue(app.routineTitle.settles(), "The title kept moving before the edit")
            app.routineTitle.tap()
            XCTAssertTrue(keyboard.appears(), "A tap on the title did not start an edit")
            app.buttons["Menu"].tap()
            XCTAssertTrue(keyboard.disappears(), "++ did not end the edit")
            XCTAssertTrue(app.drawerTitle.appears(), "++ did not open the drawer")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "A tap on the sliver left it open")
        }
        XCTContext.runActivity(named: "An edge swipe opens it, a swipe left closes it") { _ in
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
                .withOffset(CGVector(dx: 2, dy: 0))
            edge.press(
                forDuration: 0.05,
                thenDragTo: edge.withOffset(CGVector(dx: 250, dy: 0)),
                withVelocity: .default,
                thenHoldForDuration: 0,
            )
            XCTAssertTrue(app.drawerTitle.appears(), "The edge swipe did not open the drawer")
            let drawer = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
            drawer.press(
                forDuration: 0.05,
                thenDragTo: drawer.withOffset(CGVector(dx: -220, dy: 0)),
                withVelocity: .default,
                thenHoldForDuration: 0,
            )
            XCTAssertTrue(app.drawerTitle.disappears(), "The swipe left did not close the drawer")
        }
        endEditsByDragging(in: app, keyboard: keyboard)
    }

    /// A scroll, a row's hold, and a node's hold each end the edit as they start, and still do
    /// their own thing. Each drag is undone, so the reorder and superset checks after this start
    /// from the same rows.
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
            row(3).center.press(
                forDuration: 0.05,
                thenDragTo: row(3).center.down(-200),
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
        XCTContext.runActivity(named: "A node's hold ends the edit and joins the rows") { _ in
            startEdit()
            row(0).nodePoint.holdAndDrag(to: row(1).nodePoint)
            XCTAssertTrue(keyboard.disappears(), "The node's hold did not end the edit")
            XCTAssertEqual(app.supersets(becoming: "AA......."), "AA.......")
            row(1).nodePoint.holdAndDrag(to: row(0).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "........."), ".........")
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

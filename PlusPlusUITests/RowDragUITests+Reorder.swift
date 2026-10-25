import XCTest

/// Holding a row and dragging it to a new place, run within `testDragAndDeleteRows` on its
/// nine rows, which run past one screen. Where the gap goes, a drop in place included, is
/// unit-tested in the package (`RailDragTests`, `RoutineMoveTests`), and the card and gap are
/// snapshot-tested; this checks what needs real touches and the scroll view.
extension RowDragUITests {
    @MainActor
    func reorderExercises(in app: XCUIApplication) {
        let rows = app.exerciseRows
        let first = rows.element(boundBy: 0)
        // The rows in this routine are one line of name and one of plan, all one height.
        let height = rows.element(boundBy: 1).frame.minY - first.frame.minY
        XCTContext.runActivity(named: "A held row drags to a new place") { _ in
            var expected = app.exerciseNames
            attach(named: "reorder-before")
            // Past the halfway point of the second row below it.
            first.center.holdAndDrag(to: first.center.down(2.2 * height))
            expected.insert(expected.removeFirst(), at: 2)
            XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
            XCTAssertFalse(app.buttons["Sets"].exists, "The drag opened the row's sheet")
            XCTAssertFalse(app.buttons["Delete"].exists, "The drag opened the row's Delete")
            attach(named: "reorder-after")
        }
        dragToTheBottomEdge(in: app)
        XCTContext.runActivity(named: "A press that moves first scrolls the list") { _ in
            let before = (app.exerciseNames, first.frame.minY)
            let row = rows.element(boundBy: 3)
            row.center.press(
                forDuration: 0.05,
                thenDragTo: row.center.down(-200),
                withVelocity: .default,
                thenHoldForDuration: 0,
            )
            XCTAssertTrue(
                reading(first.frame.minY < before.1, becoming: true, within: 2),
                "A moving press didn't scroll the list",
            )
            XCTAssertEqual(app.exerciseNames, before.0, "A moving press moved a row")
            app.scrollToTop(titled: "Arm and back day")
        }
        XCTContext.runActivity(named: "A tap after a drag still opens the row") { _ in
            first.tap()
            let sets = app.buttons["Sets"]
            XCTAssertTrue(sets.appears(), "Tapping a row after a drag opened no sheet")
            app.buttons["Close"].tap()
            XCTAssertTrue(sets.disappears(), "Close left the sheet up")
        }
    }

    /// A row held at the bottom edge scrolls the list to its end and lands there; the list
    /// goes back to its top for the checks after it. The top edge runs through the same
    /// `railAutoscroll`, and each edge's speed and arming is `RailDragTests`'.
    @MainActor
    private func dragToTheBottomEdge(in app: XCUIApplication) {
        let first = app.exerciseRows.element(boundBy: 0)
        let start = app.buttons["Start"]
        XCTContext.runActivity(named: "A row held at the bottom edge scrolls and lands last") { _ in
            var expected = app.exerciseNames
            let top = first.frame.minY
            // Just above Start's bar: in the edge's band, still over the list.
            let edge = app.point(x: first.frame.midX, y: start.frame.minY - 24)
            first.center.holdAndDrag(to: edge, holding: 2.5)
            expected.append(expected.removeFirst())
            XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
            XCTAssertLessThan(first.frame.minY, top, "The list didn't scroll")
            attach(named: "reorder-edge")
        }
        app.scrollToTop(titled: "Arm and back day")
    }
}

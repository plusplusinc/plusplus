import XCTest

/// Holding a row and dragging it to a new place, run within `testRenameAtDefaultSize` on its
/// nine rows, which run past one screen. Where the gap goes is unit-tested in the package, and
/// the card and gap are snapshot-tested; this checks what needs real touches and the scroll view.
extension RenameUITests {
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
            first.liftPoint.holdAndDrag(to: first.liftPoint.down(2.2 * height))
            expected.insert(expected.removeFirst(), at: 2)
            XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
            XCTAssertFalse(app.buttons["Sets"].exists, "The drag opened the row's sheet")
            XCTAssertFalse(app.buttons["Delete"].exists, "The drag opened the row's Delete")
            attach(named: "reorder-after")
        }
        XCTContext.runActivity(named: "Dropping where it started changes nothing") { _ in
            let before = app.exerciseNames
            let row = rows.element(boundBy: 1)
            row.liftPoint.holdAndDrag(to: row.liftPoint.down(0.3 * height))
            XCTAssertEqual(order(keeping: before, in: app), before, "A drop in place moved the row")
        }
        XCTContext.runActivity(named: "Holding the node doesn't lift") { _ in
            let before = app.exerciseNames
            first.nodePoint.holdAndDrag(to: first.nodePoint.down(2.2 * height))
            XCTAssertEqual(order(keeping: before, in: app), before, "A hold on the node moved the row")
        }
        releaseOverStartAndAtTheEdge(in: app)
        XCTContext.runActivity(named: "A press that moves first scrolls the list") { _ in
            let before = (app.exerciseNames, first.frame.minY)
            let row = rows.element(boundBy: 3)
            row.liftPoint.press(
                forDuration: 0.05,
                thenDragTo: row.liftPoint.down(-200),
                withVelocity: .default,
                thenHoldForDuration: 0,
            )
            XCTAssertTrue(
                reading(first.frame.minY < before.1, becoming: true, within: 2),
                "A moving press didn't scroll the list",
            )
            XCTAssertEqual(app.exerciseNames, before.0, "A moving press moved a row")
            scrollToTop(in: app)
        }
        XCTContext.runActivity(named: "A tap after a drag still opens the row") { _ in
            first.tap()
            let sets = app.buttons["Sets"]
            XCTAssertTrue(sets.appears(), "Tapping a row after a drag opened no sheet")
            app.buttons["Close"].tap()
            XCTAssertTrue(sets.disappears(), "Close left the sheet up")
        }
    }

    /// A row let go over Start goes back where it was; one held at the bottom edge scrolls the
    /// list to its end and lands there.
    @MainActor
    private func releaseOverStartAndAtTheEdge(in app: XCUIApplication) {
        let first = app.exerciseRows.element(boundBy: 0)
        let start = app.buttons["Start"]
        XCTContext.runActivity(named: "Releasing over Start cancels") { _ in
            let before = app.exerciseNames
            first.liftPoint.holdAndDrag(to: start.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5),
            ))
            XCTAssertEqual(order(keeping: before, in: app), before, "A release over Start moved it")
            scrollToTop(in: app)
        }
        XCTContext.runActivity(named: "A row held at the bottom edge scrolls and lands last") { _ in
            var expected = app.exerciseNames
            let top = first.frame.minY
            // Just above Start's bar: in the edge's band, still over the list.
            let edge = app.point(x: first.frame.midX, y: start.frame.minY - 24)
            first.liftPoint.holdAndDrag(to: edge, holding: 2.5)
            expected.append(expected.removeFirst())
            XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
            XCTAssertLessThan(first.frame.minY, top, "The list didn't scroll")
            attach(named: "reorder-edge")
            scrollToTop(in: app)
        }
    }

    /// The rows' order once it changes from `before`, or `before` if it stays for a second. As
    /// the card settles, a read can miss a row offscreen, so a read of fewer rows is skipped.
    @MainActor
    private func order(keeping before: [String], in app: XCUIApplication) -> [String] {
        let deadline = Date.now.addingTimeInterval(1)
        while Date.now < deadline {
            let names = app.exerciseNames
            if names.count == before.count, names != before {
                return names
            }
        }
        return before
    }

    /// Brings the title back below the bar, with a tap on its small copy in the bar.
    @MainActor
    private func scrollToTop(in app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let smallTitle = bar.buttons["Arm and back day"]
        guard smallTitle.appears(within: 1) else { return }
        smallTitle.tap()
        XCTAssertTrue(
            reading(app.routineTitle.frame.minY >= bar.frame.maxY, becoming: true, within: 2),
            "The title did not come back below the bar",
        )
    }
}

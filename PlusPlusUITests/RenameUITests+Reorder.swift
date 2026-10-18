import XCTest

/// Holding a row and dragging it to a new place, run within `testDragAndDeleteRows` on its
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
            first.center.holdAndDrag(to: first.center.down(2.2 * height))
            expected.insert(expected.removeFirst(), at: 2)
            XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
            XCTAssertFalse(app.buttons["Sets"].exists, "The drag opened the row's sheet")
            XCTAssertFalse(app.buttons["Delete"].exists, "The drag opened the row's Delete")
            attach(named: "reorder-after")
        }
        XCTContext.runActivity(named: "Dropping where it started changes nothing") { _ in
            let before = app.exerciseNames
            let row = rows.element(boundBy: 1)
            row.center.holdAndDrag(to: row.center.down(0.3 * height))
            XCTAssertEqual(order(keeping: before, in: app), before, "A drop in place moved the row")
        }
        releaseOverStartAndAtTheEdge(in: app)
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

    /// A row let go over Start goes back where it was; one held at the bottom edge scrolls the
    /// list to its end and lands there.
    @MainActor
    private func releaseOverStartAndAtTheEdge(in app: XCUIApplication) {
        let first = app.exerciseRows.element(boundBy: 0)
        let start = app.buttons["Start"]
        XCTContext.runActivity(named: "Releasing over Start cancels") { _ in
            let before = app.exerciseNames
            first.center.holdAndDrag(to: start.center)
            XCTAssertEqual(order(keeping: before, in: app), before, "A release over Start moved it")
            app.scrollToTop(titled: "Arm and back day")
        }
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
        holdAtTheTopEdge(in: app)
    }

    /// From the end of the list, a row lifted just under the bar and held still stays put; the
    /// last row dragged up to there scrolls the list back up to its top and lands first.
    @MainActor
    private func holdAtTheTopEdge(in app: XCUIApplication) {
        let first = app.exerciseRows.element(boundBy: 0)
        let bar = app.navigationBars.firstMatch
        app.swipeUp(velocity: .fast)
        let last = app.lastExerciseRow
        XCTAssertTrue(last.settles(), "The list kept scrolling")
        // Just under the bar: in the edge's band, still over the list.
        let edge = app.point(x: last.frame.midX, y: bar.frame.maxY + 24)
        XCTContext.runActivity(named: "A row held still at the top edge stays put") { _ in
            let (names, top) = (app.exerciseNames, first.frame.minY)
            // On whichever row is there.
            edge.press(forDuration: 2.5)
            XCTAssertEqual(order(keeping: names, in: app), names, "A still hold moved the row")
            XCTAssertEqual(first.frame.minY, top, accuracy: 1, "A still hold scrolled the list")
        }
        XCTContext
            .runActivity(named: "A row dragged to the top edge scrolls up and lands first") { _ in
                var expected = app.exerciseNames
                let top = first.frame.minY
                last.center.holdAndDrag(to: edge, holding: 2.5)
                expected.insert(expected.removeLast(), at: 0)
                XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
                XCTAssertGreaterThan(first.frame.minY, top, "The list didn't scroll up")
                XCTAssertTrue(
                    reading(
                        app.routineTitle.frame.minY >= bar.frame.maxY,
                        becoming: true,
                        within: 2,
                    ),
                    "The list didn't scroll back to its top",
                )
                attach(named: "reorder-top-edge")
            }
    }

    /// The rows' order once it changes from `before`, or `before` if it stays for a second. A held
    /// row's gap draws nothing until it has settled, so it is out of the accessibility tree: a
    /// read of fewer rows is from before the drag has settled, and doesn't count.
    @MainActor
    private func order(keeping before: [String], in app: XCUIApplication) -> [String] {
        let changed = { (names: [String]) in names.count == before.count && names != before }
        let names = reading(app.exerciseNames, until: changed, within: 1)
        return names.count == before.count ? names : before
    }
}

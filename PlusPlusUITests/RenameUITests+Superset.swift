import XCTest

/// Supersets drawn by a row's node and moved into and out of by a row's body, run within
/// `testRenameAtDefaultSize` on its nine rows, after the reorder checks. What a drag makes is the
/// routine's rule, unit-tested in the package, and the field and loops are snapshot-tested; this
/// checks that real touches on the node reach the rule, and a row's VoiceOver value reads it.
/// XCTest drags in one straight move, so a drag that turns back before its drop, the span
/// shrinking under the finger, is held by the rule's tests and tried on the phone.
extension RenameUITests {
    @MainActor
    func supersetExercises(in app: XCUIApplication) {
        let rows = app.exerciseRows
        let row = { rows.element(boundBy: $0) }
        XCTContext.runActivity(named: "A node dragged onto the next row joins the two") { _ in
            attach(named: "superset-before")
            let names = app.exerciseNames
            row(0).nodePoint.holdAndDrag(to: row(1).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "AA......."), "AA.......")
            XCTAssertEqual(app.exerciseNames, names, "A drag from the node moved a row")
            XCTAssertTrue(
                app.supersetValues[0].hasPrefix("In a superset with"),
                "A member doesn't say it's in a superset",
            )
            attach(named: "superset-after")
        }
        XCTContext.runActivity(named: "A plain row's node over three rows joins four") { _ in
            row(3).nodePoint.holdAndDrag(to: row(6).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "AA.BBBB.."), "AA.BBBB..")
        }
        XCTContext.runActivity(named: "An end's node dragged inward shrinks its superset") { _ in
            row(6).nodePoint.holdAndDrag(to: row(5).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "AA.BBB..."), "AA.BBB...")
        }
        XCTContext.runActivity(named: "A middle node draws a new superset out of its own") { _ in
            row(4).nodePoint.holdAndDrag(to: row(5).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "AA..BB..."), "AA..BB...")
            attach(named: "superset-parted")
        }
        XCTContext.runActivity(named: "A node held and let go where it was changes nothing") { _ in
            let (names, groups) = (app.exerciseNames, app.supersets)
            // An end's node, which picks up its whole superset, then a plain row's.
            for index in [4, 2] {
                let node = row(index).nodePoint
                node.holdAndDrag(to: node)
                XCTAssertFalse(
                    app.buttons["Close"].appears(within: 1),
                    "Letting go of row \(index)'s node opened its sheet",
                )
                XCTAssertEqual(app.supersets, groups, "Letting go in place regrouped")
                XCTAssertEqual(app.exerciseNames, names, "Letting go in place moved a row")
            }
        }
        XCTContext.runActivity(named: "An end's node dragged onto another superset merges") { _ in
            row(1).nodePoint.holdAndDrag(to: row(5).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "AAAAAA..."), "AAAAAA...")
            attach(named: "superset-merged")
        }
        XCTContext
            .runActivity(named: "An end's node dropped on the other end leaves all plain") { _ in
                row(0).nodePoint.holdAndDrag(to: row(5).nodePoint)
                XCTAssertEqual(app.supersets(becoming: "........."), ".........")
            }
        moveRowsIntoAndOutOfASuperset(in: app)
    }

    /// A row's body carries it into a superset and back out, and a press that moves at once on
    /// the node scrolls the list.
    @MainActor
    private func moveRowsIntoAndOutOfASuperset(in app: XCUIApplication) {
        let rows = app.exerciseRows
        let row = { rows.element(boundBy: $0) }
        let height = row(1).frame.minY - row(0).frame.minY
        XCTContext.runActivity(named: "A row's body dragged into a superset joins it") { _ in
            row(0).nodePoint.holdAndDrag(to: row(1).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "AA......."), "AA.......")
            var expected = app.exerciseNames
            // Past the middle of the row above it: between the pair's two rows.
            row(2).center.holdAndDrag(to: row(2).center.down(-1.2 * height))
            expected.insert(expected.remove(at: 2), at: 1)
            XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
            XCTAssertEqual(app.supersets(becoming: "AAA......"), "AAA......")
        }
        XCTContext.runActivity(named: "A member's body dragged past the edge leaves it") { _ in
            var expected = app.exerciseNames
            // Past the last member and the plain row below it, outside both of the edge's slots.
            row(1).center.holdAndDrag(to: row(1).center.down(2.4 * height))
            expected.insert(expected.remove(at: 1), at: 3)
            XCTAssertEqual(reading(app.exerciseNames, becoming: expected, within: 2), expected)
            XCTAssertEqual(app.supersets(becoming: "AA......."), "AA.......")
        }
        XCTContext
            .runActivity(named: "A press that moves at once on a node scrolls the list") { _ in
                let before = (app.supersets, row(0).frame.minY)
                let node = row(3).nodePoint
                node.press(
                    forDuration: 0.05,
                    thenDragTo: node.down(-200),
                    withVelocity: .default,
                    thenHoldForDuration: 0,
                )
                XCTAssertTrue(
                    reading(row(0).frame.minY < before.1, becoming: true, within: 2),
                    "A moving press on a node didn't scroll the list",
                )
                XCTAssertEqual(app.supersets, before.0, "A moving press on a node regrouped")
                app.scrollToTop(titled: "Arm and back day")
            }
    }
}

@MainActor
extension XCUIApplication {
    /// Each row's VoiceOver value: whom it's in a superset with, or empty for a plain row.
    var supersetValues: [String] {
        exerciseRows.allElementsBoundByIndex.map { $0.value as? String ?? "" }
    }

    /// The rows' supersets as a letter a row: a run of members shares a letter, A for the
    /// first, and a plain row is a dot. Two supersets side by side would read as one, so the
    /// checks never make them.
    var supersets: String {
        var letters = ""
        var next = Character("A")
        for value in supersetValues {
            if value.isEmpty {
                letters.append(".")
            } else if let last = letters.last, last != "." {
                letters.append(last)
            } else {
                letters.append(next)
                next = Character(UnicodeScalar((next.asciiValue ?? 64) + 1))
            }
        }
        return letters
    }

    /// `supersets` once it reads `expected`, or what it last read after two seconds.
    func supersets(becoming expected: String) -> String {
        reading(supersets, becoming: expected, within: 2)
    }
}

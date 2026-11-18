import XCTest

/// The routine's exercise rows and the picker's, found by the identifiers the app sets.
@MainActor
extension XCUIApplication {
    private static let exerciseRowID = "routine.exercise"

    var exerciseRows: XCUIElementQuery {
        descendants(matching: .any).matching(identifier: Self.exerciseRowID)
    }

    /// The rows, top to bottom, from one snapshot, for reading every row's label or value.
    var exerciseRowSnapshots: [any XCUIElementSnapshot] {
        snapshots(identified: Self.exerciseRowID)
    }

    /// The rows' labels, top to bottom.
    var exerciseRowLabels: [String] {
        exerciseRowSnapshots.map(\.label)
    }

    /// The Routines screen's rows.
    var routineRows: XCUIElementQuery {
        buttons.matching(identifier: "routines.row")
    }

    /// The Routines screen's row labeled `name`.
    func routineRow(named name: String) -> XCUIElement {
        routineRows.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// The Routines screen's rows' labels, top to bottom.
    var routineRowLabels: [String] {
        snapshots { $0.elementType == .button && $0.identifier == "routines.row" }.map(\.label)
    }

    /// The routine's equipment, the capsules under its title.
    var equipment: XCUIElement {
        descendants(matching: .any).matching(identifier: "routine.equipment").firstMatch
    }

    /// The bottom row. Deleting it moves no other row, so the rows above are where their frames
    /// say at once. Accessibility frames are where rows end up, not where they are drawn
    /// mid-animation, so a swipe on the first row just after the one above went could land on
    /// the row below as it rose.
    var lastExerciseRow: XCUIElement {
        exerciseRows.element(boundBy: exerciseRows.count - 1)
    }

    var pickerRows: XCUIElementQuery {
        buttons.matching(identifier: "exercises.row")
    }

    /// The line an empty routine shows mid-screen.
    var noExercises: XCUIElement {
        staticTexts["No exercises"]
    }

    /// The bar's round search button, in Add exercise and Exercises, labeled Search while closed
    /// and Close search while open: there exactly while one of the two shows.
    var searchButton: XCUIElement {
        buttons["barSearch.button"]
    }

    /// The bar's search field, there to type in once the search button has opened it.
    var searchField: XCUIElement {
        textFields["barSearch.field"]
    }

    /// What VoiceOver reaches in the bar's band, beside the search button and across from it,
    /// read from one snapshot: each element's type and label, leading to trailing.
    var barElements: [String] {
        let band = searchButton.frame
        let shown = snapshots { element in
            element.elementType != .other && element.elementType != .application
                && element.elementType != .window && element.elementType != .navigationBar
                // The inline bar centers on the band, as the large title's bar did not.
                && !element.frame.isEmpty
                && element.frame.midY >= band.minY && element.frame.midY <= band.maxY
        }
        return shown.sorted { $0.frame.minX < $1.frame.minX }.map { element in
            let type = switch element.elementType {
            case .button: "button"
            case .textField: "field"
            case .image: "image"
            case .staticText: "text"
            default: "\(element.elementType.rawValue)"
            }
            return "\(type) \(element.label)"
        }
    }

    /// Opens the bar's search, unless it is open, and types `text` into its field, which opening
    /// focuses.
    func search(for text: String) {
        if searchButton.label == "Search" {
            searchButton.tap()
            XCTAssertEqual(
                searchButton.label(becoming: "Close search"),
                "Close search",
                "Search did not open",
            )
        }
        typeIntoSearch(text)
    }

    /// Types `text` into the open search key by key on the keyboard: XCTest reads the bar's
    /// field as unfocused while it has the keyboard, and its `typeText` refuses an element
    /// without focus. Letters, spaces, and deletes; Shift for a capital.
    func typeIntoSearch(_ text: String) {
        let keyboard = keyboards.element
        for character in text {
            switch character {
            case " ":
                keyboard.keys["space"].tap()
            case Character(XCUIKeyboardKey.delete.rawValue):
                keyboard.keys["delete"].tap()
            default:
                let key = keyboard.keys[String(character)]
                if !key.exists {
                    // A button, not a key.
                    keyboard.buttons["shift"].tap()
                }
                key.tap()
            }
        }
    }

    /// Opens the picker with Add exercise, the + floating over the list, which stays put as rows
    /// come in, checking that it is up within a second, and returns its search button.
    func openPicker() -> XCUIElement {
        buttons["Add exercise"].tap()
        let search = searchButton
        XCTAssertTrue(search.appears(within: 1), "The picker took over a second to open")
        return search
    }

    /// Opens the picker and picks the row labeled `label`, searching for `query` first when the
    /// row is not in the half-height sheet's first screenful. Returns once the picker is closed and
    /// the row is in.
    func addExercise(_ label: String, searching query: String? = nil) {
        let count = exerciseRows.count
        pickExercise(label, searching: query)
        XCTAssertEqual(
            exerciseCount(becoming: count + 1),
            count + 1,
            "Picking \(label) added no row",
        )
    }

    /// Opens the picker and picks the row labeled `label`, as `addExercise` does, but returns
    /// as soon as the picker is closed, while the row may still be entering.
    func pickExercise(_ label: String, searching query: String? = nil) {
        let search = openPicker()
        if let query {
            self.search(for: query)
        }
        pickerRows[label].tap()
        XCTAssertTrue(search.disappears(), "Picking \(label) left the picker open")
    }

    /// Adds a z to the search `query`, which then matches nothing, and checks that the list
    /// narrows down to its one row, Create, and returns the name Create makes. One key: each
    /// costs about half a second.
    func searchForNothing(extending query: String) -> String {
        typeIntoSearch("z")
        // Create capitalizes the first letter, and only that.
        let name = query.prefix(1).uppercased() + query.dropFirst() + "z"
        XCTAssertTrue(buttons["Create \u{201C}\(name)\u{201D}"].appears(), "No Create for \(name)")
        XCTAssertEqual(pickerRows.count, 0, "Rows other than Create match \(name)")
        return name
    }

    /// Whether the last row shows clear of Add exercise's +, once it does or after the timeout.
    /// An add that would put it under the + scrolls to the list's end once the row is in.
    func lastRowClearsAddExercise(within timeout: TimeInterval = 2) -> Bool {
        reading(
            lastExerciseRow.frame.maxY <= buttons["Add exercise"].frame.minY,
            becoming: true,
            within: timeout,
        )
    }

    /// The exercise rows' count once it is `expected`, or the last count after the timeout.
    func exerciseCount(becoming expected: Int, within timeout: TimeInterval = 2) -> Int {
        reading(exerciseRows.count, becoming: expected, within: timeout)
    }
}

extension XCUIElement {
    /// Drags left slowly and a short way, which opens a row's swipe actions and never deletes.
    func swipeOpen() {
        dragLeft(by: 100, velocity: .slow)
    }

    /// Swipes left fast and far, which deletes a row outright.
    func fullSwipeLeft() {
        dragLeft(by: 300, velocity: .fast)
    }

    /// Drags left from near the trailing edge, `distance` points at `velocity`, and lifts.
    private func dragLeft(by distance: CGFloat, velocity: XCUIGestureVelocity) {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: -distance, dy: 0)),
            withVelocity: velocity,
            thenHoldForDuration: 0,
        )
    }
}

@MainActor
extension XCUIElement {
    /// Taps the middle of the element. XCTest's `tap()` went to a stepper key's top-left corner,
    /// on the edge of the row above it, whose tap closed the stepper instead.
    func tapAtCenter() {
        center.tap()
    }

    /// The middle of the element. On a row, that is on its name and detail line, where a hold
    /// lifts it.
    var center: XCUICoordinate {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }
}

/// Holding a row and dragging it along the rail.
@MainActor
extension XCUIApplication {
    /// The rows' exercise names, top to bottom.
    var exerciseNames: [String] {
        exerciseRowLabels.map { String($0.prefix { $0 != "," }) }
    }

    /// Taps the small copy of the title `name` in the bar, and waits for the title to come back
    /// below the bar.
    func scrollToTop(titled name: String) {
        let bar = navigationBars.firstMatch
        let smallTitle = bar.buttons[name]
        XCTAssertTrue(smallTitle.appears(), "No small title in the bar")
        smallTitle.tap()
        XCTAssertTrue(
            reading(routineTitle.frame.minY >= bar.frame.maxY, becoming: true, within: 2),
            "The title did not come back below the bar",
        )
    }

    /// A point on screen, as `x` and `y` in points from its top-left corner.
    func point(x: CGFloat, y: CGFloat) -> XCUICoordinate {
        coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }
}

@MainActor
extension XCUIElement {
    /// In a row's rail column, beside its node, where a hold lifts nothing.
    var nodePoint: XCUICoordinate {
        coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 22, dy: 0))
    }
}

extension XCUICoordinate {
    /// Holds here long enough for a row to lift, drags to `target` at an unhurried hand's
    /// speed, holds there for `hold` seconds, and lets go. XCTest's `.slow`, about 200 pt/s,
    /// took most of a second a drag.
    @MainActor
    func holdAndDrag(to target: XCUICoordinate, holding hold: TimeInterval = 0.3) {
        press(
            forDuration: 0.8,
            thenDragTo: target,
            withVelocity: XCUIGestureVelocity(600),
            thenHoldForDuration: hold,
        )
    }

    /// `points` further down, or up when negative.
    func down(_ points: CGFloat) -> XCUICoordinate {
        withOffset(CGVector(dx: 0, dy: points))
    }
}

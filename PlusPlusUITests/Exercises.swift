import XCTest

/// The routine's exercise rows and the picker's, found by the identifiers the app sets.
@MainActor
extension XCUIApplication {
    var exerciseRows: XCUIElementQuery {
        descendants(matching: .any).matching(identifier: "routine.exercise")
    }

    /// The bottom row. Deleting it moves only Add exercise, so the rows above are where their
    /// frames say at once. Accessibility frames are where rows end up, not where they are drawn
    /// mid-animation, so a swipe on the first row just after the one above went could land on
    /// Add exercise as it rose, and open the picker.
    var lastExerciseRow: XCUIElement {
        exerciseRows.element(boundBy: exerciseRows.count - 1)
    }

    var pickerRows: XCUIElementQuery {
        buttons.matching(identifier: "picker.exercise")
    }

    /// Opens the picker once Add exercise has stopped moving, checking that it is up within a
    /// second, and returns its search field.
    func openPicker() -> XCUIElement {
        let addExercise = buttons["Add exercise"]
        // Just after an add it moves down as the new row's place opens.
        XCTAssertTrue(addExercise.settles(), "Add exercise kept moving")
        addExercise.tap()
        let search = searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 1), "The picker took over a second to open")
        return search
    }

    /// Opens the picker and picks the row labeled `label`, searching for `query` first when the
    /// row is not in the first screenful. Returns once the picker is closed and the row is in.
    func addExercise(_ label: String, searching query: String? = nil) {
        let count = exerciseRows.count
        let search = openPicker()
        if let query {
            search.tap()
            search.typeText(query)
        }
        pickerRows[label].tap()
        XCTAssertTrue(search.disappears(), "Picking \(label) left the picker open")
        XCTAssertEqual(
            exerciseCount(becoming: count + 1),
            count + 1,
            "Picking \(label) added no row",
        )
    }

    /// Replaces the search `query` in `search` with one nothing matches, and checks that the
    /// empty state shows.
    func searchForNothing(replacing query: String, in search: XCUIElement) {
        let delete = XCUIKeyboardKey.delete.rawValue
        search.typeText(String(repeating: delete, count: query.count) + "zzz")
        XCTAssertTrue(staticTexts["No Results for \u{201C}zzz\u{201D}"].appears())
    }

    /// Whether Add exercise shows above Start, once it does or after the timeout. An add that
    /// would push it below scrolls to it once the row is in.
    func addExerciseClearsStart(within timeout: TimeInterval = 2) -> Bool {
        let (addExercise, start) = (buttons["Add exercise"], buttons["Start"])
        return reading(addExercise.frame.maxY <= start.frame.minY, becoming: true, within: timeout)
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

extension XCUIElement {
    /// Taps the middle of the element. XCTest's `tap()` went to a stepper key's top-left corner,
    /// on the edge of the row above it, whose tap closed the stepper instead.
    @MainActor
    func tapAtCenter() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}

/// Holding a row and dragging it along the rail.
@MainActor
extension XCUIApplication {
    /// The rows' exercise names, top to bottom.
    var exerciseNames: [String] {
        exerciseRows.allElementsBoundByIndex.map { String($0.label.prefix { $0 != "," }) }
    }

    /// A point on screen, as `x` and `y` in points from its top-left corner.
    func point(x: CGFloat, y: CGFloat) -> XCUICoordinate {
        coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }
}

@MainActor
extension XCUIElement {
    /// The middle of a row, on its name and detail line, where a hold lifts it.
    var liftPoint: XCUICoordinate {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    /// In a row's rail column, beside its node, where a hold lifts nothing.
    var nodePoint: XCUICoordinate {
        coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 22, dy: 0))
    }
}

extension XCUICoordinate {
    /// Holds here long enough for a row to lift, drags slowly to `target`, holds there for
    /// `hold` seconds, and lets go.
    @MainActor
    func holdAndDrag(to target: XCUICoordinate, holding hold: TimeInterval = 0.3) {
        press(forDuration: 0.8, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: hold)
    }

    /// `points` further down, or up when negative.
    func down(_ points: CGFloat) -> XCUICoordinate {
        withOffset(CGVector(dx: 0, dy: points))
    }
}

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

    /// Opens the picker, checking that it is up within a second, and returns its search field.
    func openPicker() -> XCUIElement {
        buttons["Add exercise"].tap()
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

/// A row in an exercise's sheet, by the part it sets.
enum PlanPart: String {
    case sets
    case target
    case weight
}

@MainActor
extension XCUIApplication {
    func planRow(_ part: PlanPart) -> XCUIElement {
        descendants(matching: .any)["plan.\(part.rawValue)"]
    }

    /// Opens `part`'s wheel, or for a time its two, turns each to its value in order, and closes
    /// it again with a second tap on the row. A wheel's value is its row's text, its unit after
    /// it: "30 lb", "1 min".
    func pick(_ values: String..., for part: PlanPart) {
        planRow(part).tap()
        let wheels = pickerWheels
        XCTAssertTrue(wheels.firstMatch.appears(), "A tap on \(part) opened no wheel")
        for (index, value) in values.enumerated() {
            wheels.element(boundBy: index).adjust(toPickerWheelValue: value)
        }
        planRow(part).tap()
        XCTAssertTrue(wheels.firstMatch.disappears(), "A second tap left the wheel open")
    }

    /// Closes the sheet with its Close button, and waits for it to go.
    func closeSheet() {
        buttons["Close"].tap()
        XCTAssertTrue(planRow(.sets).disappears(), "Close left the sheet open")
    }
}

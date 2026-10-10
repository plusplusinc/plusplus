import XCTest

/// The routine's exercise rows and the picker's, found by the identifiers the app sets.
@MainActor
extension XCUIApplication {
    var exerciseRows: XCUIElementQuery {
        descendants(matching: .any).matching(identifier: "routine.exercise")
    }

    var pickerRows: XCUIElementQuery {
        buttons.matching(identifier: "picker.exercise")
    }

    /// Opens the picker, checking that it is up within a second, and picks the row labeled
    /// `label`, searching for `query` first when the row is not in the first screenful.
    func addExercise(_ label: String, searching query: String? = nil) {
        buttons["Add exercise"].tap()
        let search = searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 1), "The picker took over a second to open")
        if let query {
            search.tap()
            search.typeText(query)
        }
        pickerRows[label].tap()
        XCTAssertTrue(search.disappears(), "Picking \(label) left the picker open")
    }

    /// The exercise rows' count once it is `expected`, or the last count after the timeout.
    func exerciseCount(becoming expected: Int, within timeout: TimeInterval = 2) -> Int {
        let deadline = Date.now.addingTimeInterval(timeout)
        var count = exerciseRows.count
        while count != expected, Date.now < deadline {
            count = exerciseRows.count
        }
        return count
    }
}

extension XCTestCase {
    /// Keeps a screenshot of the whole screen with the test's results.
    @MainActor
    func attachScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

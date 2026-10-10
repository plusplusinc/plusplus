import XCTest

extension XCUIElement {
    /// XCTest's waits first check their condition about a second after they start, even when it
    /// already holds, which cost about a second a wait. These return at once when it holds.
    func appears(within timeout: TimeInterval = 2) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    func disappears(within timeout: TimeInterval = 2) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }

    /// The element's value once it is `expected`, or its last value after the timeout, for
    /// `XCTAssertEqual` to show. Typing can return before the app has handled every key, so a
    /// check that reads the screen after typing waits for the value first.
    func value(becoming expected: String, within timeout: TimeInterval = 2) -> String? {
        let deadline = Date.now.addingTimeInterval(timeout)
        var shown = value as? String
        while shown != expected, Date.now < deadline {
            shown = value as? String
        }
        return shown
    }
}

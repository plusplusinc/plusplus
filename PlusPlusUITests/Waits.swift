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

    /// Whether the element has stopped moving: its frame unchanged for `still` seconds, within
    /// the timeout. A row's place on the rail opens frame by frame, and where a view takes taps
    /// moves with it, so a tap read from a frame mid-move lands where the row is going.
    func settles(still: TimeInterval = 0.25, within timeout: TimeInterval = 2) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        var last = frame
        var since = Date.now
        while Date.now < deadline {
            let now = frame
            if now != last {
                (last, since) = (now, .now)
            } else if Date.now.timeIntervalSince(since) >= still {
                return true
            }
        }
        return false
    }

    /// The element's value once it is `expected`, or its last value after the timeout. Typing
    /// can return before the app has handled every key, so a check that reads the screen after
    /// typing waits for the value first.
    func value(becoming expected: String, within timeout: TimeInterval = 2) -> String? {
        reading(value as? String, becoming: expected, within: timeout)
    }

    /// Taps the title to edit it, and waits for the `_` at its end, where the app puts the caret
    /// once focus lands, which can come after keys sent at once.
    @MainActor
    func tapToEditAtEnd(keyboard: XCUIElement) throws {
        tap()
        XCTAssertTrue(keyboard.appears())
        let field = frame
        _ = try Ink.withCursor { try Ink.ofTitle(in: field) } until: { ink, cursor in
            ink.missAtEnd(cursor)
        }
    }
}

/// What `read` reads once it is `expected`, or its last reading after the timeout, for
/// `XCTAssertEqual` to show.
@MainActor
func reading<Value: Equatable>(
    _ read: @autoclosure () -> Value,
    becoming expected: Value,
    within timeout: TimeInterval,
) -> Value {
    reading(read(), until: { $0 == expected }, within: timeout)
}

/// What `read` reads once `done` holds for it, or its last reading after the timeout.
@MainActor
func reading<Value>(
    _ read: @autoclosure () -> Value,
    until done: (Value) -> Bool,
    within timeout: TimeInterval,
) -> Value {
    let deadline = Date.now.addingTimeInterval(timeout)
    var last = read()
    while !done(last), Date.now < deadline {
        last = read()
    }
    return last
}

/// The frames of `elements` once any of them moves, or as they are after `duration`. Whether
/// something stays put after a change shows only by watching it for a while: UIKit can move a
/// view a moment later, as it scrolls a focused field once the keyboard has risen.
@MainActor
func watchFrames(of elements: [XCUIElement], for duration: TimeInterval) -> [CGRect] {
    let start = elements.map(\.frame)
    return reading(elements.map(\.frame), until: { $0 != start }, within: duration)
}

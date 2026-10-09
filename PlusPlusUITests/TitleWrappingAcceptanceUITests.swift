import UIKit
import XCTest

/// Acceptance checks for a title that wraps at the largest accessibility text size, written from
/// the slice's criteria rather than from the code. VoiceOver frames the field, so every wrapped
/// line has to sit inside the field's frame, and the drawn `_` has to stay under the line the
/// caret is on. The lines and the `_` are read from screenshot pixels between the bar and the
/// "Add exercise" button: tall bands of ink are lines of text, thin ones are the `_`.
///
/// `nonisolated` because XCTestCase's initializers are; the tests drive the UI on the main actor.
final nonisolated class TitleWrappingAcceptanceUITests: XCTestCase {
    /// No descenders, so a thin band of ink can only be the `_`. Three lines at AX5.
    private static let threeLines = "Hot beat drills and abs"
    /// Two lines at AX5: "Arm and" and "back".
    private static let twoLines = "Arm and back"

    /// The wrapped default, "New" over "routine", sits inside the field at rest and while editing.
    @MainActor
    func testWrappedDefaultInsideFieldAtRestAndEditing() throws {
        let (app, title) = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
        try assertLinesInsideField(title, in: app, lines: 2, "at rest")

        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        try assertLinesInsideField(title, in: app, lines: 2, "editing")
    }

    /// A typed name that wraps to three lines sits inside the field while editing and after
    /// Return.
    @MainActor
    func testLongNameInsideFieldAtRestAndEditing() throws {
        let (app, title) = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        title.typeText(Self.threeLines)
        try assertLinesInsideField(title, in: app, lines: 3, "editing")

        title.typeText("\n")
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 2))
        XCTAssertEqual(title.value as? String, Self.threeLines)
        try assertLinesInsideField(title, in: app, lines: 3, "at rest")
    }

    /// Clearing a long name back to empty shows the wrapped default again, inside the field,
    /// while editing and after Return.
    @MainActor
    func testClearedNameShowsWrappedDefaultInsideField() throws {
        let (app, title) = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        title.typeText(Self.threeLines)
        let deletes = String(
            repeating: XCUIKeyboardKey.delete.rawValue,
            count: Self.threeLines.count,
        )
        title.typeText(deletes)
        try assertLinesInsideField(title, in: app, lines: 2, "cleared, editing")

        title.typeText("\n")
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 2))
        XCTAssertEqual(title.value as? String, "New routine")
        try assertLinesInsideField(title, in: app, lines: 2, "cleared, at rest")
    }

    /// With the caret on line 2, the `_` draws below line 2, not above it or under another line.
    @MainActor
    func testCursorOnLineTwoDrawsUnderLineTwo() throws {
        let (app, title) = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))

        // Line 2 is the last line: at the end, then inside "back".
        title.typeText(Self.twoLines)
        try assertCursorUnder(line: 1, of: 2, title, in: app, "end of a two-line name")
        title.typeKey(.leftArrow, modifierFlags: [])
        title.typeKey(.leftArrow, modifierFlags: [])
        try assertCursorUnder(line: 1, of: 2, title, in: app, "inside line 2 of two")

        // Line 2 is a middle line: before the "s" of "and", between lines 2 and 3.
        title.typeText(String(
            repeating: XCUIKeyboardKey.delete.rawValue,
            count: Self.twoLines.count,
        ))
        title.typeText(Self.threeLines)
        for _ in "s abs" {
            title.typeKey(.leftArrow, modifierFlags: [])
        }
        try assertCursorUnder(line: 1, of: 3, title, in: app, "inside line 2 of three")
    }

    /// At the default and at xxxLarge, "New routine" fits one line, and the field is one line
    /// tall at rest, while editing, and with a short name: no line is reserved that isn't shown.
    @MainActor
    func testOneLineSizesKeepOneLineField() throws {
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL"] {
            let (app, title) = launch(size: size)
            let atRest = title.frame
            try assertLinesInsideField(title, in: app, lines: 1, "\(size) at rest")

            title.tap()
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
            XCTAssertEqual(title.frame, atRest, "\(size): editing moved or resized the field")
            title.typeText("Legs")
            XCTAssertEqual(title.frame, atRest, "\(size): a one-line name resized the field")
            app.terminate()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func launch(size: String) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        app.launch()
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        return (app, title)
    }

    /// Every line of text on screen between the bar and "Add exercise" lies inside the field.
    @MainActor
    private func assertLinesInsideField(
        _ title: XCUIElement,
        in app: XCUIApplication,
        lines expected: Int,
        _ label: String,
        line: UInt = #line,
    ) throws {
        let bands = try XCTUnwrap(capture(title, in: app, label), line: line)
        let frame = title.frame
        XCTAssertEqual(bands.lines.count, expected, "\(label): line count", line: line)
        for (index, text) in bands.lines.enumerated() {
            XCTAssertGreaterThanOrEqual(
                text.lowerBound,
                frame.minY - 1,
                "\(label): line \(index + 1) starts above the field \(frame)",
                line: line,
            )
            XCTAssertLessThanOrEqual(
                text.upperBound,
                frame.maxY + 1,
                "\(label): line \(index + 1) ends below the field \(frame)",
                line: line,
            )
        }
        let button = app.buttons["Add exercise"].frame
        XCTAssertLessThanOrEqual(frame.maxY, button.minY, "\(label): field overlaps the button")
    }

    /// The `_` sits below the given line (zero-based): above the next line's glyphs, or, under
    /// the last line, less than a line's height below it. Where in the gap between two lines it
    /// sits is the maintainer's call (dropped from slice 2), so this does not judge it.
    @MainActor
    private func assertCursorUnder(
        line target: Int,
        of count: Int,
        _ title: XCUIElement,
        in app: XCUIApplication,
        _ label: String,
        line: UInt = #line,
    ) throws {
        let deadline = Date.now.addingTimeInterval(2.2)
        var found: Bands?
        while Date.now < deadline, found == nil {
            if let bands = capture(title, in: app, label, attach: false), bands.cursor != nil {
                found = bands
            }
        }
        let bands = try XCTUnwrap(found, "\(label): no _ over two blink cycles", line: line)
        attach(label)
        XCTAssertEqual(bands.lines.count, count, "\(label): line count", line: line)
        let cursor = try XCTUnwrap(bands.cursor, line: line)
        let above = bands.lines[target]
        XCTAssertGreaterThan(
            cursor.lowerBound,
            above.upperBound,
            "\(label): _ not below",
            line: line,
        )
        if target + 1 < bands.lines.count {
            let below = bands.lines[target + 1]
            XCTAssertLessThan(cursor.upperBound, below.lowerBound, "\(label): _ hits next line")
        } else {
            // Below the last line by less than a line's height: under it, not a line further.
            XCTAssertLessThan(
                cursor.lowerBound - above.upperBound,
                above.upperBound - above.lowerBound,
                "\(label): _ hangs too far below the last line",
                line: line,
            )
        }
    }

    @MainActor
    private func attach(_ label: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name) \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The ink bands in the field's column, from just under the bar down to "Add exercise", in
    /// points.
    @MainActor
    private func capture(
        _ title: XCUIElement,
        in app: XCUIApplication,
        _ label: String,
        attach shouldAttach: Bool = true,
    ) -> Bands? {
        let screenshot = XCUIScreen.main.screenshot()
        if shouldAttach {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "\(name) \(label)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        guard let image = screenshot.image.cgImage else { return nil }
        let scale = CGFloat(image.width) / screenshot.image.size.width
        let field = title.frame
        let top = field.minY - 16
        let bottom = app.buttons["Add exercise"].frame.minY - 1
        let strip = CGRect(x: field.minX, y: top, width: field.width, height: bottom - top)
        let pixels = CGRect(
            x: strip.minX * scale,
            y: strip.minY * scale,
            width: strip.width * scale,
            height: strip.height * scale,
        )
        guard let cropped = image.cropping(to: pixels.integral) else { return nil }
        return Bands(cropped, scale: scale, top: top)
    }
}

/// Runs of rows holding ink, in screen points: tall runs are lines of text, a thin one the `_`.
private struct Bands {
    var lines: [Range<CGFloat>] = []
    var cursor: Range<CGFloat>?

    init?(_ image: CGImage, scale: CGFloat, top: CGFloat) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // The strip starts above the field, on plain background.
        let background = Array(pixels[0 ..< 3])
        let inked = (0 ..< height).map { y in
            (0 ..< width).contains { x in
                let index = (y * width + x) * 4
                return zip(pixels[index ..< index + 3], background)
                    .reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) } > 60
            }
        }
        var start: Int?
        var runs: [Range<Int>] = []
        for (y, ink) in inked.enumerated() {
            if ink, start == nil {
                start = y
            } else if !ink, let first = start {
                runs.append(first ..< y)
                start = nil
            }
        }
        if let first = start {
            runs.append(first ..< height)
        }
        for run in runs {
            let points = (top + CGFloat(run.lowerBound) / scale) ..<
                (top + CGFloat(run.upperBound) / scale)
            if points.upperBound - points.lowerBound > 8 {
                lines.append(points)
            } else {
                cursor = points
            }
        }
    }
}

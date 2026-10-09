import UIKit
import XCTest

/// Renaming through the keyboard: Return has to end editing and keep the name, an empty name has
/// to fall back to the default, and the `_` cursor has to sit where typing goes. The rules are
/// unit-tested in the package; this checks that real key presses reach them, which no simulator
/// tool could press, and reads the `_` from the pixels, since it is drawn, not an element.
///
/// `nonisolated` because XCTestCase's initializers are; the tests themselves drive the UI from
/// the main actor.
final nonisolated class RenameUITests: XCTestCase {
    @MainActor
    func testReturnCommitsAndEmptyRestoresDefault() {
        let (app, title) = launchToTitle()

        rename(title, in: app, typing: "Legs\n", expecting: "Legs")
        rename(title, in: app, typing: " day\n", expecting: "Legs day")
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Legs day".count)
        rename(title, in: app, typing: deletes + "\n", expecting: "New routine")
    }

    /// Starting an edit must not move the title by even a pixel, and the default shows as a
    /// placeholder with the `_` under its first letter.
    @MainActor
    func testEditingStartsInPlaceWithCursorUnderPlaceholder() throws {
        let (app, title) = launchToTitle()

        let addExercise = app.buttons["Add exercise"]
        let frameAtRest = title.frame
        let buttonAtRest = addExercise.frame
        let atRest = try XCTUnwrap(titleImage(title).flatMap(TitleInk.init))
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertEqual(title.frame, frameAtRest)
        XCTAssertEqual(addExercise.frame, buttonAtRest)
        let editing = try cursorShown(in: title)
        XCTAssertEqual(editing.text, atRest.text, "The title moved sideways when editing started")
        XCTAssertEqual(editing.textTop, atRest.textTop, "The title moved down when editing started")

        let cursor = try XCTUnwrap(editing.cursor)
        let letters = try XCTUnwrap(editing.text)
        XCTAssertLessThan(abs(cursor.lowerBound - letters.lowerBound), 8, "The _ should be under N")
        XCTAssertLessThan(cursor.upperBound, letters.lowerBound + 40, "The _ should be under N")
    }

    /// The `_` follows the caret into the middle of the name, and typing and deleting there edit
    /// the middle.
    @MainActor
    func testCursorFollowsCaretInsideName() throws {
        let (app, title) = launchToTitle()

        // No descenders, so any ink under the baseline is the `_`.
        title.tap()
        title.typeText("Arm back")
        let atEnd = try XCTUnwrap(cursorShown(in: title).cursor)

        for _ in "back" {
            title.typeKey(.leftArrow, modifierFlags: [])
        }
        let beforeB = try cursorShown(in: title)
        let cursor = try XCTUnwrap(beforeB.cursor)
        let letters = try XCTUnwrap(beforeB.text)
        XCTAssertLessThan(cursor.upperBound, atEnd.lowerBound, "The _ should leave the end")
        XCTAssertGreaterThan(cursor.lowerBound, letters.lowerBound, "The _ should be inside")

        title.typeText("and  " + XCUIKeyboardKey.delete.rawValue)
        let afterTyping = try cursorShown(in: title)
        let moved = try XCTUnwrap(afterTyping.cursor)
        let longer = try XCTUnwrap(afterTyping.text)
        XCTAssertGreaterThan(moved.lowerBound, cursor.lowerBound, "The _ should move on")
        XCTAssertLessThan(moved.upperBound, longer.upperBound, "The _ should stay inside")

        title.typeText("\n")
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 2),
            "Return should end editing",
        )
        XCTAssertEqual(title.value as? String, "Arm and back")
    }

    @MainActor
    private func launchToTitle() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launch()
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        return (app, title)
    }

    /// The screen under the title's field, and the strip just below it where the `_` hangs.
    @MainActor
    private func titleImage(_ title: XCUIElement) -> CGImage? {
        let screen = XCUIScreen.main.screenshot().image
        guard let image = screen.cgImage else { return nil }
        let scale = CGFloat(image.width) / screen.size.width
        let frame = title.frame
        let strip = CGRect(
            x: frame.minX * scale,
            y: frame.minY * scale,
            width: frame.width * scale,
            height: (frame.height + Self.cursorDrop) * scale,
        )
        return image.cropping(to: strip.integral)
    }

    /// Room below the field for the `_`, which hangs past it, but not as far as the next view.
    private static let cursorDrop: CGFloat = 12

    /// Taps the title, types, and checks that the Return at the end of `text` ended editing and
    /// left `expected` behind.
    @MainActor
    private func rename(
        _ title: XCUIElement,
        in app: XCUIApplication,
        typing text: String,
        expecting expected: String,
        line: UInt = #line,
    ) {
        title.tap()
        title.typeText(text)
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 2),
            "Return should end editing",
            line: line,
        )
        XCTAssertEqual(title.value as? String, expected, line: line)
    }

    /// The title's ink while the blinking `_` is on: it is off half of each 1.06s cycle, so this
    /// looks for it over two cycles.
    @MainActor
    private func cursorShown(in title: XCUIElement) throws -> TitleInk {
        let deadline = Date.now.addingTimeInterval(2.2)
        while Date.now < deadline {
            if let image = titleImage(title), let ink = TitleInk(image), ink.cursor != nil {
                return ink
            }
        }
        throw CursorNotFound()
    }
}

/// Where a title's glyphs and `_` are, in pixel columns, read from a screenshot of the field. The
/// `_` hangs below the baseline with a gap above it, so in a name without descenders the first
/// band of inked rows is the text and the next one is the `_`.
private struct TitleInk {
    /// The columns of the text's ink, and its top row.
    let text: ClosedRange<Int>?
    let textTop: Int?
    /// The columns of the `_`.
    let cursor: ClosedRange<Int>?

    init?(_ cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
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
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // The far right of the field is past any short name: background.
        let background = Array(pixels[(width - 1) * 4 ..< width * 4 - 1])
        let rows = (0 ..< height).map { y in
            (0 ..< width).filter { x in
                let index = (y * width + x) * 4
                let distance = zip(pixels[index ..< index + 3], background)
                    .reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
                return distance > 60
            }
        }
        let bands = Self.bands(rows)
        text = bands.first.flatMap { Self.columns(rows[$0]) }
        textTop = bands.first?.lowerBound
        cursor = bands.dropFirst().first.flatMap { Self.columns(rows[$0]) }
    }

    /// Runs of consecutive rows that hold ink.
    private static func bands(_ rows: [[Int]]) -> [Range<Int>] {
        var bands: [Range<Int>] = []
        var start: Int?
        for (y, row) in rows.enumerated() {
            if !row.isEmpty, start == nil {
                start = y
            } else if row.isEmpty, let first = start {
                bands.append(first ..< y)
                start = nil
            }
        }
        if let first = start {
            bands.append(first ..< rows.count)
        }
        return bands
    }

    private static func columns(_ rows: ArraySlice<[Int]>) -> ClosedRange<Int>? {
        let all = rows.joined()
        guard let low = all.min(), let high = all.max() else { return nil }
        return low ... high
    }
}

private struct CursorNotFound: Error { }

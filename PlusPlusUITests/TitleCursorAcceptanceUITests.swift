import UIKit
import XCTest

/// Acceptance checks for the title's drawn `_` cursor and the keyboard around it, written from
/// the maintainer's device feedback rather than from the code. The `_` is drawn, not an element,
/// so these read it from screenshot pixels: inside the field's frame and a strip below it, in
/// pixel columns and rows.
///
/// `nonisolated` because XCTestCase's initializers are; the tests drive the UI on the main actor.
final nonisolated class TitleCursorAcceptanceUITests: XCTestCase {
    /// Starting an edit on the default name shows it as gray placeholder text, dimmer than at
    /// rest, with the `_` under its first letter.
    @MainActor
    func testDefaultNameTurnsGrayWhenEditingStarts() throws {
        let (app, title) = launch()
        let atRest = try XCTUnwrap(shot(of: title))
        let restInk = try XCTUnwrap(atRest.brightestInk(in: atRest.textRows))

        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        let editing = try cursorShown(in: title)
        let editingInk = try XCTUnwrap(editing.brightestInk(in: editing.textRows))
        XCTAssertLessThan(editingInk, restInk - 40, "The default name should turn gray")
        let cursor = try XCTUnwrap(editing.cursorColumns)
        let text = try XCTUnwrap(editing.textColumns)
        XCTAssertLessThan(abs(cursor.lowerBound - text.lowerBound), 8, "The _ should be under N")
    }

    /// A range selection hides the `_`; collapsing it back to a caret brings the `_` back.
    @MainActor
    func testRangeSelectionHidesCursor() throws {
        let (app, title) = launch()
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        title.typeText("Arm back")
        let caret = try cursorShown(in: title)
        let unselected = caret.differingPixels(in: caret.textRows)

        for _ in "back" {
            title.typeKey(.leftArrow, modifierFlags: .shift)
        }
        // Over two blink cycles, no frame may show the `_`.
        let deadline = Date.now.addingTimeInterval(2.2)
        var selected: Ink?
        while Date.now < deadline {
            let frame = try XCTUnwrap(shot(of: title))
            XCTAssertNil(frame.cursorColumns, "A range selection should not show the _")
            selected = frame
        }
        // The highlight fills the selected cells' background, so far more of the line differs
        // from the screen background than the glyphs alone.
        let highlighted = try XCTUnwrap(selected).differingPixels(in: caret.textRows)
        XCTAssertGreaterThan(highlighted, unselected + 2000, "The selection should be highlighted")

        title.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertNoThrow(try cursorShown(in: title), "A collapsed selection should show the _")
    }

    /// Tapping the start of a word while editing moves the `_` under that word's first letter.
    @MainActor
    func testTapMovesCursorUnderTappedWord() throws {
        let (app, title) = launch()
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        title.typeText("Arm back")
        let atEnd = try cursorShown(in: title)
        let text = try XCTUnwrap(atEnd.textColumns)
        // Monospaced: eight equal cells from the A's left edge to the k's right edge, roughly.
        let cell = Double(text.count) / 8
        let bStart = Double(text.lowerBound) + 4 * cell

        let point = (bStart + 0.2 * cell) / atEnd.scale
        title.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point, dy: title.frame.height / 2))
            .tap()
        let moved = try cursorShown(in: title, awayFrom: atEnd.cursorColumns)
        let cursor = try XCTUnwrap(moved.cursorColumns)
        XCTAssertLessThan(
            abs(Double(cursor.lowerBound) - bStart),
            cell / 2,
            "The _ should sit under the b of back",
        )
    }

    /// The `_` under a letter with a descender stays clear of it: the tail and the `_` are two
    /// separate bands of ink with background between them.
    @MainActor
    func testCursorClearsDescenders() throws {
        let (app, title) = launch()
        title.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        title.typeText("gym yoga")
        for _ in "yoga" {
            title.typeKey(.leftArrow, modifierFlags: [])
        }
        // Throws when the `_` merges into the y's tail, since then there is no second band.
        let underY = try cursorShown(in: title, awayFrom: nil)
        let cursor = try XCTUnwrap(underY.cursorColumns)
        let text = try XCTUnwrap(underY.textColumns)
        let cell = Double(text.count) / 8
        XCTAssertLessThan(
            abs(Double(cursor.lowerBound) - (Double(text.lowerBound) + 4 * cell)),
            cell / 2,
            "The _ should sit under the y of yoga",
        )
    }

    /// No hard edge or band at the keyboard's top corners: just outside its rounded glass, the
    /// screen's own background shows.
    @MainActor
    func testScreenBackgroundRunsBehindKeyboardCorners() throws {
        let (app, title) = launch()
        title.tap()
        let keyboard = app.keyboards.element
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        // Let the keyboard finish rising.
        let settled = expectation(
            for: NSPredicate { _, _ in keyboard.isHittable },
            evaluatedWith: nil,
        )
        wait(for: [settled], timeout: 2)
        let screen = XCUIScreen.main.screenshot()
        let image = try XCTUnwrap(screen.image.cgImage)
        let pixels = try XCTUnwrap(Pixels(image))
        let scale = Double(image.width) / screen.image.size.width
        let top = keyboard.frame.minY
        let background = pixels.color(x: 200 * scale, y: (top - 60) * scale)

        let attachment = XCTAttachment(screenshot: screen)
        attachment.name = "keyboard-corners"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Rows just above the keyboard and the corners just inside its frame's top edge.
        let samples: [(Double, Double)] = [
            (4, top - 2), (200, top - 2), (398, top - 2),
            (keyboard.frame.minX + 2, top + 2), (keyboard.frame.maxX - 2, top + 2),
        ]
        for (x, y) in samples {
            let color = pixels.color(x: x * scale, y: y * scale)
            let distance = zip(color, background).reduce(0) { $0 + abs($1.0 - $1.1) }
            XCTAssertLessThan(distance, 24, "A band at (\(x), \(y)): \(color) vs \(background)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func launch() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launch()
        let title = app.textFields["Routine name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        return (app, title)
    }

    /// The field and a strip below it for the `_`, short of the next view.
    @MainActor
    private func shot(of title: XCUIElement) -> Ink? {
        let screen = XCUIScreen.main.screenshot().image
        guard let image = screen.cgImage else { return nil }
        let scale = Double(image.width) / screen.size.width
        let frame = title.frame
        let strip = CGRect(
            x: frame.minX * scale,
            y: frame.minY * scale,
            width: frame.width * scale,
            height: (frame.height + 12) * scale,
        )
        return image.cropping(to: strip.integral).flatMap { Ink($0, scale: scale) }
    }

    /// A frame with the `_` lit, over two blink cycles; with `awayFrom`, one whose `_` has left
    /// those columns.
    @MainActor
    private func cursorShown(
        in title: XCUIElement,
        awayFrom old: ClosedRange<Int>? = nil,
    ) throws -> Ink {
        let deadline = Date.now.addingTimeInterval(2.2)
        while Date.now < deadline {
            if let ink = shot(of: title), let cursor = ink.cursorColumns,
               old.map({ abs($0.lowerBound - cursor.lowerBound) > 6 }) ?? true
            {
                return ink
            }
        }
        throw CursorNotShown()
    }
}

/// RGBA pixels of an image, read once.
private struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        bytes = buffer
    }

    func color(x: Double, y: Double) -> [Int] {
        let column = min(max(Int(x), 0), width - 1)
        let row = min(max(Int(y), 0), height - 1)
        let index = (row * width + column) * 4
        return bytes[index ..< index + 3].map(Int.init)
    }
}

/// Where the title's text and `_` are. The background is the far right column of the field,
/// past any short name. Rows that hold ink form bands: the first is the text (descenders
/// included), the next, below a background gap, is the `_`.
private struct Ink {
    let pixels: Pixels
    let scale: Double
    let background: [Int]
    let rows: [[Int]]
    let bands: [Range<Int>]

    init?(_ image: CGImage, scale: Double) {
        guard let pixels = Pixels(image) else { return nil }
        self.pixels = pixels
        self.scale = scale
        let background = pixels.color(x: Double(pixels.width - 1), y: 0)
        self.background = background
        rows = (0 ..< pixels.height).map { y in
            (0 ..< pixels.width).filter { x in
                let color = pixels.color(x: Double(x), y: Double(y))
                return zip(color, background).reduce(0) { $0 + abs($1.0 - $1.1) } > 60
            }
        }
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
        self.bands = bands
    }

    var textRows: Range<Int> {
        bands.first ?? 0 ..< 0
    }

    var textColumns: ClosedRange<Int>? {
        bands.first.flatMap(columns)
    }

    var cursorColumns: ClosedRange<Int>? {
        bands.dropFirst().first.flatMap(columns)
    }

    private func columns(_ band: Range<Int>) -> ClosedRange<Int>? {
        let all = rows[band].joined()
        guard let low = all.min(), let high = all.max() else { return nil }
        return low ... high
    }

    /// The brightest pixel's mean channel value within the rows.
    func brightestInk(in band: Range<Int>) -> Int? {
        band.flatMap { y in
            rows[y].map { x in pixels.color(x: Double(x), y: Double(y)).reduce(0, +) / 3 }
        }.max()
    }

    /// How many pixels in the rows differ from the background.
    func differingPixels(in band: Range<Int>) -> Int {
        band.filter { $0 < rows.count }.reduce(0) { $0 + rows[$1].count }
    }
}

private struct CursorNotShown: Error { }

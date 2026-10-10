import UIKit
import XCTest

/// A screenshot read as pixels. The title's `_` is drawn, not an element, so the UI tests find it,
/// and the title's lines, as runs of inked rows in a strip of the screen.
struct TitleShot {
    let screenshot: XCUIScreenshot
    /// Pixels per point.
    let scale: CGFloat
    private let image: CGImage

    @MainActor
    init() throws {
        screenshot = XCUIScreen.main.screenshot()
        image = try XCTUnwrap(screenshot.image.cgImage)
        scale = CGFloat(image.width) / screenshot.image.size.width
    }

    /// How far apart two colors are: the sum of their channels' differences.
    static func distance(_ one: [Int], _ other: [Int]) -> Int {
        zip(one, other).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    /// The red, green, and blue at a point on screen.
    func color(at point: CGPoint) throws -> [Int] {
        try pixels(in: CGRect(origin: point, size: CGSize(width: 1, height: 1))).color(0, 0)
    }

    /// The ink in a strip of the screen, both given in points: pixels that differ from the color
    /// at `background` by more than 60, summed over the three channels.
    func ink(in strip: CGRect, background: CGPoint) throws -> Ink {
        let pixels = try pixels(in: strip)
        let paper = try color(at: background)
        // Inline rather than `distance`, which allocates per pixel in a Debug build.
        let inked = (0 ..< pixels.height).map { row in
            (0 ..< pixels.width).filter { column in
                let index = (row * pixels.width + column) * 4
                let bytes = pixels.bytes
                return abs(Int(bytes[index]) - paper[0]) + abs(Int(bytes[index + 1]) - paper[1])
                    + abs(Int(bytes[index + 2]) - paper[2]) > 60
            }
        }
        return Ink(shot: self, top: pixels.top, inked: inked)
    }

    /// Only the pixels of a rectangle in points, since decoding the whole screen for a strip
    /// would cost more than reading it.
    private func pixels(in rect: CGRect) throws -> Pixels {
        let crop = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale,
        ).integral
        let part = try XCTUnwrap(image.cropping(to: crop), "\(rect) is off screen")
        return try Pixels(part, top: Int(crop.minY))
    }
}

/// The RGBA bytes of part of a screenshot, and how far down the screen it starts, in pixels.
struct Pixels {
    let width: Int
    let height: Int
    let top: Int
    let bytes: [UInt8]

    fileprivate init(_ image: CGImage, top: Int) throws {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
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
        guard drawn else { throw UnreadableScreenshot() }
        self.width = width
        self.height = height
        self.top = top
        bytes = buffer
    }

    func color(_ column: Int, _ row: Int) -> [Int] {
        let index = (row * width + column) * 4
        return bytes[index ..< index + 3].map(Int.init)
    }
}

/// Where the ink in a strip is. Runs of inked rows taller than 8pt are lines of text, descenders
/// included. A thinner run is the `_`, which hangs below its line with background between them.
struct Ink {
    /// A run of inked rows: its rows within the strip, its top and bottom on screen in points,
    /// and the pixel columns its ink spans, counted from the strip's left edge.
    struct Run {
        let rows: Range<Int>
        let points: Range<CGFloat>
        let columns: ClosedRange<Int>

        /// Where character `index` of a monospaced run of `count` characters starts, and a
        /// character's width, in pixel columns. Roughly: the ink runs from the first glyph's
        /// left edge to the last one's right edge, not cell edge to cell edge.
        func cell(_ index: Int, of count: Int) -> (start: Double, width: Double) {
            let width = Double(columns.count) / Double(count)
            return (Double(columns.lowerBound) + Double(index) * width, width)
        }
    }

    /// The `_` blinks on and off every 0.53s. Over two cycles a `_` that is there shows.
    static let twoBlinks: TimeInterval = 2.2

    let shot: TitleShot
    let lines: [Run]
    let cursor: Run?
    private let inked: [[Int]]

    /// `top` is how far down the screen the strip starts, in pixels.
    fileprivate init(shot: TitleShot, top: Int, inked: [[Int]]) {
        self.shot = shot
        self.inked = inked
        var runs: [Range<Int>] = []
        var start: Int?
        for (row, columns) in inked.enumerated() {
            if !columns.isEmpty, start == nil {
                start = row
            } else if columns.isEmpty, let first = start {
                runs.append(first ..< row)
                start = nil
            }
        }
        if let first = start {
            runs.append(first ..< inked.count)
        }
        var lines: [Run] = []
        var cursor: Run?
        for rows in runs {
            let all = inked[rows].joined()
            guard let low = all.min(), let high = all.max() else { continue }
            let run = Run(
                rows: rows,
                points: CGFloat(top + rows.lowerBound) / shot.scale ..<
                    CGFloat(top + rows.upperBound) / shot.scale,
                columns: low ... high,
            )
            if run.points.upperBound - run.points.lowerBound > 8 {
                lines.append(run)
            } else {
                cursor = run
            }
        }
        self.lines = lines
        self.cursor = cursor
    }

    /// How many pixels within the rows differ from the background.
    func differingPixels(in rows: Range<Int>) -> Int {
        rows.clamped(to: inked.indices).reduce(0) { $0 + inked[$1].count }
    }

    /// Reads ink until the `_` is lit where `miss` finds nothing wrong with it. Key presses and
    /// taps can return before the app has handled them, so a read after one waits for the state
    /// it checks. After two blink cycles it throws with the last miss, or with none if the `_`
    /// never lit.
    @MainActor
    static func withCursor(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ read: () throws -> Self,
        until miss: (Self, _ cursor: Run) -> String?,
    ) throws -> Self {
        let deadline = Date.now.addingTimeInterval(twoBlinks)
        var last = "No _ over two blink cycles"
        while Date.now < deadline {
            let ink = try read()
            guard let cursor = ink.cursor else { continue }
            guard let wrong = miss(ink, cursor) else { return ink }
            last = wrong
        }
        return try XCTUnwrap(nil as Self?, last, file: file, line: line)
    }
}

private struct UnreadableScreenshot: Error { }

extension XCTestCase {
    /// Keeps the screenshot in the result bundle, pass or fail.
    @MainActor
    func attach(_ shot: TitleShot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot.screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

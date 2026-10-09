import UIKit
import XCTest

/// A screenshot read as pixels. The title's `_` is drawn, not an element, so the UI tests find it,
/// and the title's lines, as runs of inked rows in a strip of the screen.
struct TitleShot {
    let screenshot: XCUIScreenshot
    /// Pixels per point.
    let scale: CGFloat
    private let width: Int
    private let height: Int
    private let bytes: [UInt8]

    @MainActor
    init() throws {
        screenshot = XCUIScreen.main.screenshot()
        let image = try XCTUnwrap(screenshot.image.cgImage)
        scale = CGFloat(image.width) / screenshot.image.size.width
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
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
        bytes = buffer
    }

    /// How far apart two colors are: the sum of their channels' differences.
    static func distance(_ one: [Int], _ other: [Int]) -> Int {
        zip(one, other).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    /// The red, green, and blue at a point on screen.
    func color(at point: CGPoint) -> [Int] {
        color(column: Int(point.x * scale), row: Int(point.y * scale))
    }

    private func color(column: Int, row: Int) -> [Int] {
        let index = (min(max(row, 0), height - 1) * width + min(max(column, 0), width - 1)) * 4
        return bytes[index ..< index + 3].map(Int.init)
    }

    /// The ink in a strip of the screen, both given in points: pixels that differ from the color
    /// at `background` by more than 60, summed over the three channels.
    func ink(in strip: CGRect, background: CGPoint) -> Ink {
        let left = Int(strip.minX * scale)
        let top = Int(strip.minY * scale)
        let columns = max(min(Int(strip.maxX * scale), width) - left, 0)
        let rows = max(min(Int(strip.maxY * scale), height) - top, 0)
        let paper = color(at: background)
        // Inline rather than `distance`, which allocates per pixel in a Debug build.
        let inked = (0 ..< rows).map { row in
            (0 ..< columns).filter { column in
                let index = ((top + row) * width + left + column) * 4
                return abs(Int(bytes[index]) - paper[0]) + abs(Int(bytes[index + 1]) - paper[1])
                    + abs(Int(bytes[index + 2]) - paper[2]) > 60
            }
        }
        return Ink(shot: self, left: left, top: top, inked: inked)
    }

    fileprivate func brightness(column: Int, row: Int) -> Int {
        color(column: column, row: row).reduce(0, +) / 3
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
    private let left: Int
    private let top: Int
    private let inked: [[Int]]

    fileprivate init(shot: TitleShot, left: Int, top: Int, inked: [[Int]]) {
        self.shot = shot
        self.left = left
        self.top = top
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

    /// The brightest inked pixel's mean channel value within the rows.
    func brightestInk(in rows: Range<Int>) -> Int? {
        rows.flatMap { row in
            inked[row].map { shot.brightness(column: left + $0, row: top + row) }
        }.max()
    }

    /// How many pixels within the rows differ from the background.
    func differingPixels(in rows: Range<Int>) -> Int {
        rows.clamped(to: inked.indices).reduce(0) { $0 + inked[$1].count }
    }

    /// Reads ink until the `_` is lit, and fails after two blink cycles without it. With
    /// `awayFrom`, the `_` also has to have left those columns.
    @MainActor
    static func withCursor(
        awayFrom old: ClosedRange<Int>? = nil,
        _ read: () throws -> Self,
    ) throws -> Self {
        let deadline = Date.now.addingTimeInterval(twoBlinks)
        while Date.now < deadline {
            let ink = try read()
            if let cursor = ink.cursor,
               old.map({ abs($0.lowerBound - cursor.columns.lowerBound) > 6 }) ?? true
            {
                return ink
            }
        }
        return try XCTUnwrap(nil as Self?, "No _ over two blink cycles")
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

// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// As a workout moves on to a superset's next member, the space above the current exercise's
/// label moves from one row to the other on the move's animation, and the rows' frames
/// interpolate to their new heights. A row's own stretch of loop was drawn from its height at the
/// move's end at once, inside a row still drawn at its height before, so the loop broke for the
/// whole move. Read from the frames drawn while it plays.
@MainActor
@Suite("Rail moves on")
struct RailMoveTests {
    @Observable
    final class Workout {
        var current = 0
        var isMoving = false
    }

    private struct Row: Identifiable {
        let id: Int
        let title: String
    }

    private struct Host: View {
        let workout: Workout
        private let rows = [
            Row(id: 0, title: "Goblet squat"),
            Row(id: 1, title: "Reverse lunge"),
            Row(id: 2, title: "Step-up"),
        ]

        var body: some View {
            Rail(rows, links: [0], current: workout.current, isMoving: workout.isMoving) { row in
                RowLabel(title: row.title, detail: ["3 × 10 reps"])
                    // As the routine screen gives the current exercise (`currentTopSpace`).
                    .padding(.top, row.id == workout.current ? 24 : 0)
                    .railRow()
            } end: {
                EmptyView()
            }
            .padding(Self.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.pp(.background))
        }

        static let inset: CGFloat = 16
    }

    /// The loop's column in the window: the rail's nodes are at the middle of its 44 pt column,
    /// past the room before it, and the loop runs beside them as the default text size's pen puts
    /// it.
    private static let loopX = Host.inset
        + LoopPen(lineWidth: railLineWidth, scale: 1, offset: 12).runX(nodeX: railColumnLead + 22)

    /// Each frame shown while the move plays, the loop's column read from it: whether each pixel
    /// down it differs from the background.
    private final class Frames: NSObject {
        let window: UIWindow
        private(set) var columns: [[Bool]] = []

        init(window: UIWindow) {
            self.window = window
        }

        @objc func frame(_: CADisplayLink) {
            columns.append(column())
        }

        private func column() -> [Bool] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let width = 4
            let height = Int(window.bounds.height)
            let image = UIGraphicsImageRenderer(
                size: CGSize(width: width, height: height),
                format: format,
            ).image { context in
                // The layers as the frame shows them, mid-move: in a window with no scene,
                // `drawHierarchy` draws nothing.
                context.cgContext.translateBy(x: -RailMoveTests.loopX + 2, y: 0)
                window.layer.render(in: context.cgContext)
            }
            guard let cgImage = image.cgImage else { return [] }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            // The background, from the column's top, above the rail.
            let background = Array(pixels[(2 * 4) ..< (2 * 4 + 3)])
            return (0 ..< height).map { row in
                let start = (row * width + 2) * 4
                return zip(pixels[start ..< start + 3], background)
                    .contains { abs(Int($0) - Int($1)) > 24 }
            }
        }
    }

    /// The longest stretch down the loop's column, between its first drawn point and its last,
    /// with nothing drawn.
    private func longestBreak(_ column: [Bool]) -> Break {
        guard let first = column.firstIndex(of: true), let last = column.lastIndex(of: true)
        else { return Break(length: 0, at: 0, drawn: 0) }
        var longest = (length: 0, at: 0)
        var run = 0
        for y in first ... last {
            run = column[y] ? 0 : run + 1
            if run > longest.length {
                longest = (run, y - run + 1)
            }
        }
        return Break(length: longest.length, at: longest.at, drawn: last - first)
    }

    /// A break in the loop's column, in points: how long and where, and how long the loop is
    /// from its first drawn point to its last.
    private struct Break {
        var length: Int
        var at: Int
        var drawn: Int
    }

    @Test(
        "While rows move on an animation, a superset's loop shows no break on any frame",
        arguments: [(from: 0, to: 1), (from: 1, to: 0)],
    )
    func unbroken(way: (from: Int, to: Int)) throws {
        let workout = Workout()
        workout.current = way.from
        let window = UIWindow.sceneless(
            hosting: UIHostingController(rootView: Host(workout: workout)),
            at: .large,
        )
        window.overrideUserInterfaceStyle = .dark
        defer { window.isHidden = true }
        window.settle()

        let frames = Frames(window: window)
        let link = CADisplayLink(target: frames, selector: #selector(Frames.frame(_:)))
        workout.isMoving = true
        window.settle()
        withAnimation(.linear(duration: 0.4)) {
            workout.current = way.to
        }
        link.add(to: .main, forMode: .common)
        defer { link.invalidate() }
        let deadline = Date.now.addingTimeInterval(1.2)
        while frames.columns.count < 12, Date.now < deadline {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
        }
        try #require(
            frames.columns.count >= 12,
            "the screen showed only \(frames.columns.count) frames",
        )

        // A head's gap is 3 pt, and its antialiased edges a point either side.
        for (index, column) in frames.columns.enumerated() {
            let gap = longestBreak(column)
            #expect(gap.drawn > 40, "frame \(index): the loop is \(gap.drawn) pt long")
            #expect(
                gap.length <= 5,
                "frame \(index): the loop breaks for \(gap.length) pt at y \(gap.at)",
            )
        }
    }
}

#endif

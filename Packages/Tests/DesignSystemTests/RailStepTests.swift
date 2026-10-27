// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// While a held row scrolls the list, or the room above the rail moves, the list steps a frame
/// at a time on a frame clock, which is read once a frame. Read again by the update a step
/// starts, it could give the next frame's date in the same frame, and the list stepped twice,
/// which SwiftUI logs as an `onChange(of: Date)` fault. The fault only shows when that update
/// runs long, as on the routine screen, so this counts the reads.
///
/// The clock also has to keep going. One inserted as the list started stepping could stop after
/// its first date, most often when the hold began about half a frame after the last, and the
/// list stayed where it was (`RailFrames`). So each hold here begins half a frame after one, and
/// the list is held and let go several times.
@MainActor
@Suite("Rail steps once a frame")
struct RailStepTests {
    /// The edges the hosted list shares with its rows.
    private final class EdgesBox {
        var edges: RailEdges?
    }

    private struct Host: View {
        let box: EdgesBox
        @State private var position = ScrollPosition()

        var body: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0 ..< 60, id: \.self) { index in
                        Text("Row \(index)").frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .background(EdgesReader(box: box))
            }
            .scrollPosition($position)
            .railAutoscroll($position)
        }
    }

    private struct EdgesReader: View {
        let box: EdgesBox
        @Environment(\.railEdges) private var edges

        var body: some View {
            Color.clear.onAppear { box.edges = edges }
        }
    }

    /// When the main thread was last told of a new frame on the screen, and how long one lasts.
    private final class Screen: NSObject {
        private(set) var frames = 0
        private(set) var lastFrame: CFTimeInterval = 0
        private(set) var frameLength: CFTimeInterval = 0

        @objc func frame(_ link: CADisplayLink) {
            frames += 1
            lastFrame = CACurrentMediaTime()
            frameLength = link.targetTimestamp - link.timestamp
        }

        /// Returns half a frame after the main thread is told of the screen's next frame, where
        /// a clock inserted then stopped most often: in a sweep across the frame, in about half
        /// the holds started 7 to 9 ms in, and in none started 2 ms or more either side. It
        /// spins for that last part, since running the run loop could start an update.
        func waitHalfAFrame() {
            let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link.add(to: .main, forMode: .common)
            defer { link.invalidate() }
            let seen = frames
            let deadline = Date.now.addingTimeInterval(1)
            while frames == seen, Date.now < deadline {
                RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.001))
            }
            let start = lastFrame + frameLength / 2
            while CACurrentMediaTime() < start { }
        }
    }

    /// A row held in the bottom edge's band, which scrolls the list a frame at a time for as
    /// long as it is held, then let go, six times over.
    @Test("The frame clock keeps going, read once a frame, each time the list steps")
    func readOncePerFrame() throws {
        let box = EdgesBox()
        let host = UIHostingController(rootView: Host(box: box))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        let edges = try #require(box.edges)
        let bottom = window.bounds.height
        let screen = Screen()

        for hold in 1 ... 6 {
            var reads: [Date] = []
            edges.frameRead = { reads.append($0) }
            screen.waitHalfAFrame()
            edges.lift(at: bottom / 2) { _, _ in }
            edges.move(to: bottom - 20)
            try #require(edges.isStepping, "a row held in the bottom band doesn't scroll the list")
            let deadline = Date.now.addingTimeInterval(5)
            while Set(reads).count < 10, edges.isStepping, Date.now < deadline {
                RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
            }
            edges.letGo()

            let frames = Set(reads).count
            try #require(frames >= 10, "hold \(hold): the list stepped for only \(frames) frames")
            #expect(
                reads.count == frames,
                "hold \(hold): the clock was read \(reads.count) times in \(frames) frames",
            )
        }
    }
}

#endif

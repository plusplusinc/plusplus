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
@MainActor
@Suite("Rail steps once a frame")
struct RailStepTests {
    /// Every date the frame clock was read at.
    private final class Log {
        var reads: [Date] = []
        var edges: RailEdges?
    }

    private struct Host: View {
        let log: Log
        @State private var position = ScrollPosition()

        var body: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0 ..< 60, id: \.self) { index in
                        Text("Row \(index)").frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .background(EdgesReader(log: log))
            }
            .scrollPosition($position)
            .railAutoscroll($position)
        }
    }

    private struct EdgesReader: View {
        let log: Log
        @Environment(\.railEdges) private var edges

        var body: some View {
            Color.clear.onAppear { log.edges = edges }
        }
    }

    enum Motion: String, CaseIterable {
        /// A row held in the bottom edge's band, so the list scrolls.
        case edge
        /// A row held where it lifted, its room above the rail opening.
        case room
    }

    @Test("The frame clock is read once a frame while the list steps", arguments: Motion.allCases)
    func readOncePerFrame(motion: Motion) throws {
        let log = Log()
        let host = UIHostingController(rootView: Host(log: log))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        let edges = try #require(log.edges)
        edges.frameRead = { log.reads.append($0) }

        let bottom = window.bounds.height
        edges.lift(at: bottom / 2, room: 80) { _, _ in }
        switch motion {
        case .edge: edges.move(to: bottom - 20)
        case .room: edges.aim(room: 80, animated: true)
        }
        let deadline = Date.now.addingTimeInterval(5)
        while Set(log.reads).count < 20, edges.isStepping, Date.now < deadline {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
        }
        edges.letGo()

        let frames = Set(log.reads).count
        try #require(frames >= 10, "\(motion): the list stepped for only \(frames) frames")
        #expect(
            log.reads.count == frames,
            "\(motion): the clock was read \(log.reads.count) times in \(frames) frames",
        )
    }
}

#endif

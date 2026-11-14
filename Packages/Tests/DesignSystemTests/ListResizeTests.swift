// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import QuartzCore
import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// A list's rows resizing on an animation (`listResizes(_:)`), as at a workout's Start and End:
/// the list reads as resizing from the update that starts it until that animation has really
/// ended. Both were cleared from the animation's completion, which SwiftUI sometimes ran before
/// the first frame while the rows went on resizing: a superset's loop heads stopped easing and
/// jumped, and at End the room under the list went at once and the list slammed to its top.
/// Read from a hosted view over the frames the animation plays on, in that worst order: the
/// room's own flag goes, with no animation, in the update after the one that starts it.
@MainActor
@Suite("List resizes")
struct ListResizeTests {
    @Observable
    final class Content {
        var height: CGFloat = 1200
        var isMakingRoom = true
        var resizes = 0
        var position = ScrollPosition()
    }

    /// When the rows inside read the list as resizing, and when they stop.
    private final class Reads {
        var changes: [(time: CFTimeInterval, isResizing: Bool)] = []
    }

    private struct Probe: View {
        let reads: Reads
        @Environment(\.isListResizing) private var isResizing

        var body: some View {
            Color.clear
                .onChange(of: isResizing, initial: true) {
                    reads.changes.append((CACurrentMediaTime(), isResizing))
                }
        }
    }

    private struct Host: View {
        @Bindable var list: Content
        let reads: Reads

        var body: some View {
            ScrollView {
                Probe(reads: reads)
                    .frame(height: list.height)
                    .frame(maxWidth: .infinity)
                    .roomBelow(list.isMakingRoom)
                    .listResizes(list.resizes)
            }
            .scrollPosition($list.position)
        }
    }

    /// The scroll view's content height on every frame while the animation plays.
    private final class Frames: NSObject {
        let scroll: UIScrollView
        private(set) var heights: [(time: CFTimeInterval, height: CGFloat)] = []

        init(scroll: UIScrollView) {
            self.scroll = scroll
        }

        @objc func frame(_: CADisplayLink) {
            heights.append((CACurrentMediaTime(), scroll.contentSize.height))
        }
    }

    private static let duration = 0.4

    /// A list scrolled down with the room under its end on shrinks its rows on an animation, as
    /// End does, and the room's own flag goes in the next update, as a completion run early did.
    /// One run of the frames for both guarantees, as each costs the animation's time.
    @Test("""
    The list reads as resizing from the update that starts the animation until it ends, and \
    the room under it stays until then
    """)
    func roomStaysWhileRowsResize() throws {
        let list = Content()
        let reads = Reads()
        let window = UIWindow.sceneless(
            hosting: UIHostingController(rootView: Host(list: list, reads: reads)),
            at: .large,
        )
        defer { window.isHidden = true }
        window.settle()
        list.position.scrollTo(y: 600)
        window.settle()
        let scroll = try #require(window.firstScrollView, "No scroll view hosted")
        let scrolled = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let visible = scroll.bounds.height - scroll.adjustedContentInset.top
            - scroll.adjustedContentInset.bottom

        let frames = Frames(scroll: scroll)
        let link = CADisplayLink(target: frames, selector: #selector(Frames.frame(_:)))
        let start = CACurrentMediaTime()
        withAnimation(.linear(duration: Self.duration)) {
            list.height = 300
            list.resizes += 1
        }
        // The update that starts it, before any frame.
        window.layoutIfNeeded()
        #expect(
            reads.changes.last?.isResizing == true,
            "The update that starts the animation reads it as done",
        )
        withTransaction(\.disablesAnimations, true) { list.isMakingRoom = false }
        window.layoutIfNeeded()
        frames.frame(link)
        link.add(to: .main, forMode: .common)
        defer { link.invalidate() }
        // Until a few frames after it reads as done, or well past the animation's end.
        let deadline = Date.now.addingTimeInterval(Self.duration + 0.4)
        var ended: CFTimeInterval?
        while Date.now < deadline, ended.map({ CACurrentMediaTime() - $0 < 0.05 }) ?? true {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
            ended = ended ?? reads.changes.last { !$0.isResizing && $0.time > start }?.time
        }

        let end = try #require(ended, "Still resizing after the animation")
        #expect(
            end - start > Self.duration * 0.9,
            "Read as done \(end - start) s into a \(Self.duration) s animation",
        )
        let heights = frames.heights
        try #require(heights.count >= 12, "Only \(heights.count) frames shown")
        // The first frame: room for the list to stay where it is scrolled to, not the shrunk
        // rows' end, which clamped it to its top.
        #expect(
            heights[0].height >= scrolled + visible,
            "First frame's content \(heights[0].height) pt, scrolled to \(scrolled) pt",
        )
        // Until the animation is nearly over, the content follows its curve, a step a frame.
        let during = heights.filter { $0.time - start < Self.duration * 0.9 }
        let steps = zip(during, during.dropFirst()).map { $0.height - $1.height }
        #expect(steps.allSatisfy { $0 < visible / 4 }, "Steps: \(steps)")
        // Once it is over, the room has gone: only the rows are left.
        #expect(heights.last?.height ?? 0 < scrolled, "Ends \(heights.last?.height ?? 0) pt")
    }
}

#endif

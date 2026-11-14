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

    private struct Run {
        let frames: Frames
        let reads: Reads
        let start: CFTimeInterval
        /// What the update that starts the animation read, before any frame.
        let isFirstResizing: Bool
        /// How far the list was scrolled, and how much of it shows.
        let scrolled: CGFloat
        let visible: CGFloat
    }

    private static let duration = 0.4

    private static func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView {
            return scroll
        }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    /// Hosts a list scrolled down with the room under its end on, then shrinks its rows on an
    /// animation, as End does, and turns the room's own flag off in the next update, as a
    /// completion run early did. Plays the frames until a little past the animation's end.
    private func end() throws -> Run {
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
        let scroll = try #require(Self.scrollView(in: window), "No scroll view hosted")
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
        let first = reads.changes.last?.isResizing ?? false
        withTransaction(\.disablesAnimations, true) { list.isMakingRoom = false }
        window.layoutIfNeeded()
        frames.frame(link)
        link.add(to: .main, forMode: .common)
        defer { link.invalidate() }
        let deadline = Date.now.addingTimeInterval(Self.duration + 0.4)
        while Date.now < deadline {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
        }
        return Run(
            frames: frames,
            reads: reads,
            start: start,
            isFirstResizing: first,
            scrolled: scrolled,
            visible: visible,
        )
    }

    @Test("The list reads as resizing from the update that starts the animation until it ends")
    func readsResizingForTheWholeAnimation() throws {
        let run = try end()
        #expect(run.isFirstResizing, "The update that starts the animation reads it as done")
        let ended = try #require(
            run.reads.changes.last { !$0.isResizing && $0.time > run.start },
            "Still resizing after the animation",
        )
        #expect(
            ended.time - run.start > Self.duration * 0.9,
            "Read as done \(ended.time - run.start) s into a \(Self.duration) s animation",
        )
    }

    @Test("While the rows shrink, the room under the list stays, and goes once they have")
    func roomStaysWhileRowsShrink() throws {
        let run = try end()
        let heights = run.frames.heights
        try #require(heights.count >= 12, "Only \(heights.count) frames shown")
        // The first frame: room for the list to stay where it is scrolled to, not the shrunk
        // rows' end, which clamped it to its top.
        #expect(
            heights[0].height >= run.scrolled + run.visible,
            "First frame's content \(heights[0].height) pt, scrolled to \(run.scrolled) pt",
        )
        // Until the animation is nearly over, the content follows its curve, a step a frame.
        let during = heights.filter { $0.time - run.start < Self.duration * 0.9 }
        let steps = zip(during, during.dropFirst()).map { $0.height - $1.height }
        #expect(steps.allSatisfy { $0 < run.visible / 4 }, "Steps: \(steps)")
        // Once it is over, the room has gone: only the rows are left.
        #expect(heights.last?.height ?? 0 < run.scrolled, "Ends \(heights.last?.height ?? 0) pt")
    }
}

#endif

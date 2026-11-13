// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The room that lets a list land a row under the bar (`roomToLand(top:)`): while it is on, the
/// content is never too short for the scroll view to reach the landing, so the room under the
/// list's end (`roomBelow`) can go at any moment, with the rows above at any height. Read from a
/// hosted scroll view, whose offset the scroll view clamps to its content in every layout pass.
/// What this cannot hold is the scroll view's own content size trailing the content's on an
/// animation, as it does through Start's grow: the room has to be at its height before that
/// animation starts, which only the running app shows.
@MainActor
@Suite("Landing room")
struct LandingRoomTests {
    @Observable
    final class Content {
        var height: CGFloat = 900
        var isMakingRoom = true
        var position = ScrollPosition()
    }

    private struct Host: View {
        @Bindable var list: Content
        let landing: CGFloat?

        var body: some View {
            ScrollView {
                Color.clear
                    .frame(height: list.height)
                    .frame(maxWidth: .infinity)
                    .roomToLand(top: landing)
                    .roomBelow(list.isMakingRoom)
            }
            .scrollPosition($list.position)
        }
    }

    /// Where `landing` leaves the list once the room under its end goes in the same update as the
    /// content shrinking to `height`, the worst order: scrolled to 200 with the room on, then both
    /// at once.
    private func restingOffset(landing: CGFloat?, height: CGFloat) throws -> CGFloat {
        let list = Content()
        let host = UIHostingController(rootView: Host(list: list, landing: landing))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        window.settle()
        list.position.scrollTo(y: Self.landing)
        window.settle()
        let scroll = try #require(Self.scrollView(in: window), "No scroll view hosted")
        #expect(scroll.contentOffset.y + scroll.adjustedContentInset.top == Self.landing)
        withTransaction(\.disablesAnimations, true) {
            list.height = height
            list.isMakingRoom = false
        }
        window.settle()
        return scroll.contentOffset.y + scroll.adjustedContentInset.top
    }

    private static let landing: CGFloat = 200

    private static func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView {
            return scroll
        }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    @Test(
        "With the landing's room on, the room under the list going leaves the list at its landing",
        arguments: [CGFloat(40), 400, 1400],
    )
    func roomHoldsTheLanding(height: CGFloat) throws {
        #expect(try restingOffset(landing: Self.landing, height: height) == Self.landing)
    }

    @Test("Without the landing's room, the same order clamps the list short of its landing")
    func noRoomClamps() throws {
        #expect(try restingOffset(landing: nil, height: 40) < Self.landing)
    }
}

#endif

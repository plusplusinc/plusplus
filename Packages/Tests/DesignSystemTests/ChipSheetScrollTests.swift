// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing
import UIKit

/// A chip sheet whose chips fit stays still under a drag. The sheet stands at its content's
/// height and hands its content the home indicator's room as a bottom safe area, even where it
/// floats clear of it; a scroll view that took that room as an inset had more content than it
/// showed, and scrolled by it. Read from a hosted sheet given what the system gives it, since
/// the system sheet itself shows only in the running app.
@MainActor
@Suite("Chip sheet scrolling")
struct ChipSheetScrollTests {
    private static let room: CGFloat = 34

    @Test("Chips that fit leave the sheet nothing to scroll under the home indicator's room")
    func fittingChipsStayStill() throws {
        let host = UIHostingController(rootView: ChipSheet(
            title: "Muscle",
            items: ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"],
            chosen: .constant([]),
            name: { $0 },
            onDone: { },
        ))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        window.settle()
        let scroll = try #require(window.firstScrollView, "No scroll view hosted")
        // The content's own height, as the sheet measures it for its detent: down to the end
        // of what the scroll view holds.
        let content = scroll.convert(scroll.bounds, to: window).minY - scroll.contentOffset.y
            - scroll.adjustedContentInset.top + scroll.contentSize.height

        // What the sheet gives it: that height, with the room as a bottom safe area.
        window.frame.size.height = content
        host.additionalSafeAreaInsets.bottom = Self.room
        window.settle()

        let range = scroll.contentSize.height + scroll.adjustedContentInset.top
            + scroll.adjustedContentInset.bottom - scroll.bounds.height
        #expect(range <= 0.5, "The chips scroll by \(range) pt")
    }
}

#endif

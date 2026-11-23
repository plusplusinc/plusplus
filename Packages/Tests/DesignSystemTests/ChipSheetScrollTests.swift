// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing
import UIKit

/// A chip sheet whose chips fit stays still under a drag. The sheet opens at half height and
/// hands its content the home indicator's room as a bottom safe area, even where it floats
/// clear of it; a scroll view that takes that room as an inset has more content than it
/// shows, and scrolls by it. Read from a hosted sheet given what the system gives it, since
/// the system sheet itself shows only in the running app.
@MainActor
@Suite("Chip sheet scrolling")
struct ChipSheetScrollTests {
    private static let room: CGFloat = 34

    @Test("Chips that fit at half height leave the sheet nothing to scroll")
    func fittingChipsStayStill() throws {
        let host = UIHostingController(rootView: ChipSheet(
            title: "Muscle",
            items: ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"],
            chosen: .constant([]),
            name: { $0 },
            onDone: { },
        ))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        // What the sheet gives it at `.medium`: half the screen, with the room as a bottom
        // safe area.
        window.frame.size.height /= 2
        host.additionalSafeAreaInsets.bottom = Self.room
        window.settle()
        let scroll = try #require(window.firstScrollView, "No scroll view hosted")

        let range = scroll.contentSize.height + scroll.adjustedContentInset.top
            + scroll.adjustedContentInset.bottom - scroll.bounds.height
        #expect(range <= 0.5, "The chips scroll by \(range) pt")
    }
}

#endif

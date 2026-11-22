import SwiftUI
import Testing
@testable import DesignSystem

/// A row's swipe actions compare equal while what they show and act on is, whatever closure
/// made them, so SwiftUI keeps the ones it built rather than building them again on each run of
/// the screen's body (`rowSwipe(_:value:action:)`). That SwiftUI skips an equal modifier's body
/// in the frame a screen's rows first lay out was read on the simulator, from the fault log and
/// the body's runs; a hosted window ran the body again in some runs and not in others.
@Suite("Row swipes")
struct RowSwipeTests {
    /// Made anew on each call, as a screen's body makes it on each run.
    private func swipe(_ title: LocalizedStringKey = "Remove", value: Int) -> RowSwipe<Int> {
        var removed: Int?
        return RowSwipe(title: title, value: value) { removed = $0 }
    }

    @Test("Swipe actions made by new closures for the same row are equal")
    func equalAcrossClosures() {
        let (first, again) = (swipe(value: 1), swipe(value: 1))
        #expect(first == again)
    }

    @Test("Swipe actions for a new value or title are not equal")
    func unequalForNewValueOrTitle() {
        #expect(swipe(value: 1) != swipe(value: 2))
        #expect(swipe("Remove", value: 1) != swipe("Delete", value: 1))
    }
}

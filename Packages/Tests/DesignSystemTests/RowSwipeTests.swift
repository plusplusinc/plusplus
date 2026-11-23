import SwiftUI
import Testing
@testable import DesignSystem

/// A row's swipe actions compare equal while what they show and act on is, whatever closure
/// made them, so SwiftUI keeps the ones it built rather than building them again on each run of
/// the screen's body (`rowSwipe(_:value:action:)`). That SwiftUI then skips an equal modifier's
/// body was read on the simulator, from the fault log and the body's runs at an add and a drop;
/// at some first layouts it ran the body with no compare, and a hosted window did either.
@Suite("Row swipes")
struct RowSwipeTests {
    /// Made anew on each call, as a screen's body makes it on each run: the closure captures its
    /// own storage, so no two calls' closures are the same.
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

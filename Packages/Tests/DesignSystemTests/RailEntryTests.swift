import SwiftUI
import Testing
@testable import DesignSystem

/// The add's entry: when the haptic fires, and the blue's hold and fade, read from the keyframes
/// the rail plays. A simulator cannot feel a haptic, so its timing is what is tested.
@Suite("Rail entry timeline")
struct RailEntryTests {
    @Test("With Reduce Motion, the row lands at once")
    func landingWithReduceMotion() {
        #expect(RailEntry.popStart(reduceMotion: true) == 0)
    }

    @Test("The blue holds through the landing and the hold, then fades on an ease-out")
    func joiningSettles() {
        let timeline = KeyframeTimeline(initialValue: 0.0) { RailEntry.joining() }
        let landing = RailEntry.popStart(reduceMotion: false)
        let held = landing + RailEntry.pop + RailEntry.hold
        #expect(timeline.value(time: landing) == 1)
        #expect(timeline.value(time: held) == 1)
        #expect(timeline.value(time: held + RailEntry.settle / 2) < 0.5)
        #expect(timeline.value(time: held + RailEntry.settle) == 0)
    }
}

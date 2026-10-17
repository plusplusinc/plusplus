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

    @Test("The node, the content, and the haptic land as the line reaches the node")
    func landingMeetsLine() {
        #expect(RailEntry.popStart(reduceMotion: false) == RailEntry.shot)
    }

    @Test("The blue holds through the landing and the hold, then fades on an ease-out")
    func joiningSettles() {
        let landing = RailEntry.popStart(reduceMotion: false)
        let timeline = KeyframeTimeline(initialValue: 0.0) { RailEntry.joining(after: landing) }
        let held = landing + RailEntry.pop + RailEntry.hold
        #expect(timeline.value(time: landing) == 1)
        #expect(timeline.value(time: held) == 1)
        #expect(timeline.value(time: held + RailEntry.settle / 2) < 0.5)
        #expect(timeline.value(time: held + RailEntry.settle) == 0)
    }

    @Test("A group a node's drag made flashes as a node lands, once the field has faded")
    func groupFlash() {
        let node = KeyframeTimeline(initialValue: 0.0) {
            RailEntry.joining(after: RailEntry.popStart(reduceMotion: false))
        }
        let group = KeyframeTimeline(initialValue: 0.0) { RailEntry.groupFlash() }
        let wait = RailEntry.fieldFade
        let lag = wait - RailEntry.popStart(reduceMotion: false)
        #expect(abs(group.duration - node.duration - lag) < 1e-9)
        #expect(group.value(time: wait / 2) == 0)
        #expect(group.value(time: wait + 0.01) == 1)
        let fade = RailEntry.pop + RailEntry.hold + RailEntry.settle / 2
        #expect(group.value(time: wait + fade) == node.value(time: RailEntry.shot + fade))
    }
}

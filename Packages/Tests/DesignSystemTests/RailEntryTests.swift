import SwiftUI
import Testing
@testable import DesignSystem

/// The add's entry timeline: when the commit haptic fires, and the blue's settle, read from the
/// keyframes the rail plays. A simulator cannot feel a haptic, so its timing is what is tested.
@Suite("Rail entry timeline")
struct RailEntryTests {
    @Test("The haptic fires as the line hits, when the node and the text land")
    func commitOnLanding() {
        let time = RailEntry.commitTime(lead: 0.15, isFirst: false, reduceMotion: false)
        #expect(abs(time - (0.15 + RailEntry.shot)) < 1e-9)
        #expect(time == 0.15 + RailEntry.popStart(isFirst: false, reduceMotion: false))
    }

    @Test("On the first row, with no line, the node, text, and haptic land at once")
    func commitOnFirstRow() {
        #expect(RailEntry.commitTime(lead: 0.15, isFirst: true, reduceMotion: false) == 0.15)
    }

    @Test("The blue holds through the pop and is gone by about 1.05 s after the row shows")
    func joiningSettles() {
        let lead = 0.15
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            RailEntry.joining(lead: lead, isFirst: false)
        }
        let pop = lead + RailEntry.popStart(isFirst: false, reduceMotion: false)
        #expect(timeline.value(time: pop) == 1)
        #expect(timeline.value(time: pop + RailEntry.hold) == 1)
        #expect(timeline.value(time: lead + 1.05) == 0)
    }
}

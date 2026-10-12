import SwiftUI
import Testing
@testable import DesignSystem

/// The add's entry timeline: when the commit haptic fires, and the blue's settle, read from the
/// keyframes the rail plays. A simulator cannot feel a haptic, so its timing is what is tested.
@Suite("Rail entry timeline")
struct RailEntryTests {
    @Test("The haptic fires as the line lands and the node pops", arguments: [0, 0.15])
    func commitOnLanding(lead: TimeInterval) {
        let time = RailEntry.commitTime(lead: lead, isFirst: false, reduceMotion: false)
        #expect(abs(time - (lead + RailEntry.shotStart + RailEntry.shot)) < 1e-9)
    }

    @Test("On the first row, with no line, the haptic fires as the name finishes")
    func commitOnFirstRow() {
        let time = RailEntry.commitTime(lead: 0.15, isFirst: true, reduceMotion: false)
        #expect(abs(time - (0.15 + RailEntry.firstPop)) < 1e-9)
        #expect(RailEntry.firstPop < RailEntry.name)
    }

    @Test("With Reduce Motion, the haptic still fires, as the row shows")
    func commitWithReduceMotion() {
        #expect(RailEntry.commitTime(lead: 0.15, isFirst: false, reduceMotion: true) == 0.15)
    }

    @Test("The blue holds through the pop and is gone by 0.6 s after the row shows")
    func joiningSettles() {
        let lead = 0.15
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            RailEntry.joining(lead: lead, isFirst: false)
        }
        let pop = lead + RailEntry.popStart(isFirst: false, reduceMotion: false)
        #expect(timeline.value(time: pop) == 1)
        #expect(timeline.value(time: pop + RailEntry.hold) == 1)
        #expect(timeline.value(time: lead + 0.6) == 0)
    }
}

import SwiftUI
import Testing
@testable import DesignSystem

/// The add's entry timeline: when the commit haptic fires, and the blue's settle, read from the
/// keyframes the rail plays. A simulator cannot feel a haptic, so its timing is what is tested.
@Suite("Rail entry timeline")
struct RailEntryTests {
    @Test("The haptic fires once, as the name lands, before the rail's flourish")
    func commitOnNameLanding() {
        #expect(abs(RailEntry.commitTime(lead: 0.15) - (0.15 + RailEntry.name)) < 1e-9)
        #expect(RailEntry.name < RailEntry.shotStart)
        #expect(RailEntry.name < RailEntry.popStart(isFirst: true, reduceMotion: false))
    }

    @Test("The rail follows the name after a beat of about a tenth of a second")
    func beatBeforeShot() {
        let beat = RailEntry.shotStart - RailEntry.name
        #expect(beat >= 0.1 && beat <= 0.17)
    }

    @Test("The blue holds through the pop and is gone by about 0.8 s after the row shows")
    func joiningSettles() {
        let lead = 0.15
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            RailEntry.joining(lead: lead, isFirst: false)
        }
        let pop = lead + RailEntry.popStart(isFirst: false, reduceMotion: false)
        #expect(timeline.value(time: pop) == 1)
        #expect(timeline.value(time: pop + RailEntry.hold) == 1)
        #expect(timeline.value(time: lead + 0.8) == 0)
    }
}

import SwiftUI
import Testing
@testable import DesignSystem

/// The add's entry: when the haptic fires, the blue's hold and fade, read from the keyframes the
/// rail plays, and the pulse's shape. A simulator cannot feel a haptic, so its timing is what is
/// tested.
@Suite("Rail entry timeline")
struct RailEntryTests {
    @Test("The haptic fires as the line hits, when the node and the text land")
    func commitOnLanding() {
        let time = RailEntry.commitTime(lead: 0.15, isFirst: false, reduceMotion: false)
        #expect(abs(time - (0.15 + RailEntry.start + RailEntry.shot + RailEntry.pause)) < 1e-9)
        #expect(time == 0.15 + RailEntry.popStart(isFirst: false, reduceMotion: false))
    }

    @Test("On the first row, with no line, the place opens over the shot's time, then it lands")
    func commitOnFirstRow() {
        let first = RailEntry.commitTime(lead: 0.15, isFirst: true, reduceMotion: false)
        let other = RailEntry.commitTime(lead: 0.15, isFirst: false, reduceMotion: false)
        #expect(first == other)
    }

    @Test("With Reduce Motion, the haptic still fires, as the row lands at once")
    func commitWithReduceMotion() {
        #expect(RailEntry.commitTime(lead: 0.15, isFirst: false, reduceMotion: true) == 0.15)
    }

    @Test("The haptic and the landing come after a short start, the shot, and a pause")
    func landingSequence() {
        #expect(RailEntry.start > 0)
        #expect(RailEntry.pause > 0)
        let landing = RailEntry.popStart(isFirst: false, reduceMotion: false)
        #expect(abs(landing - (RailEntry.start + RailEntry.shot + RailEntry.pause)) < 1e-9)
    }

    /// The pulse for a 64-point gap, landing at y = 100, at `time`.
    private func pulse(at time: Double) -> CGRect {
        Pulse(
            time: time,
            node: CGPoint(x: 20, y: 100),
            gap: 64,
            lineWidth: 2,
            duration: RailEntry.shot,
            end: RailEntry.pulseEnd,
        )
        .path(in: .zero)
        .boundingRect
    }

    @Test("The pulse starts as a dot of the line's width under the node above")
    func pulseStartsAsDot() {
        let start = pulse(at: 0)
        #expect(abs(start.width - 2) < 0.01)
        #expect(start.height < 2 * 2)
        #expect(abs(start.maxY - (100 - 64)) < 0.01)
    }

    @Test("The pulse stretches with speed, to at most 35% of the gap, longest before impact")
    func pulseStretches() {
        let lengths = stride(from: 0.0, through: 1.0, by: 0.05).map { pulse(at: $0).height }
        #expect(lengths.allSatisfy { $0 <= 64 * 0.35 + 0.01 })
        #expect(zip(lengths, lengths.dropFirst()).allSatisfy { $0 <= $1 + 0.01 })
        #expect(abs(pulse(at: 1).maxY - 100) < 0.01)
        #expect(abs(pulse(at: 1).width - 2 * RailEntry.pointScale) < 0.01)
    }

    @Test("Through the pause the pulse collapses into the dot the node pops from")
    func pulseCollapses() {
        let end = pulse(at: RailEntry.pulseEnd)
        #expect(abs(end.width - 2 * RailEntry.pointScale) < 0.01)
        #expect(abs(end.height - end.width) < 0.01)
    }

    @Test("The blue holds through the pop and is gone by about 1.15 s after the row shows")
    func joiningSettles() {
        let lead = 0.15
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            RailEntry.joining(lead: lead, isFirst: false)
        }
        let pop = lead + RailEntry.popStart(isFirst: false, reduceMotion: false)
        #expect(timeline.value(time: pop) == 1)
        let settled = pop + RailEntry.pop + RailEntry.pause
        #expect(timeline.value(time: settled + RailEntry.hold) == 1)
        #expect(timeline.value(time: lead + 1.15) == 0)
    }
}

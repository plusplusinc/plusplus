import SwiftUI
import Testing
@testable import DesignSystem

/// The current node's beat as a set logs that stays on its exercise, read from the keyframes the
/// node plays: held from the log until the key is back at the start, then popped back.
@Suite("Set beat")
struct SetBeatTests {
    @Test("As a set logs, the node shrinks to half and grays, and rests so")
    func holds() {
        let timeline = KeyframeTimeline(initialValue: SetBeat()) { SetBeat.keyframes(held: true) }
        let middle = timeline.value(time: 0.1)
        #expect(middle.scale < 1 && middle.scale > 0.5)
        #expect(middle.gray > 0 && middle.gray < 1)
        let held = timeline.value(time: timeline.duration)
        #expect(held.scale == 0.5)
        #expect(held.gray == 1)
    }

    @Test("Let go, it pops back past its full size, green again, and settles at it")
    func pops() {
        let timeline = KeyframeTimeline(initialValue: SetBeat(held: true)) {
            SetBeat.keyframes(held: false)
        }
        let steps = stride(from: 0.0, through: timeline.duration, by: 1.0 / 120)
        let largest = steps.map { timeline.value(time: $0).scale }.max() ?? 0
        #expect(largest > 1.02)
        #expect(timeline.value(time: 0.12).gray == 0)
        let end = timeline.value(time: timeline.duration)
        #expect(abs(end.scale - 1) < 0.01)
        #expect(end.gray == 0)
    }
}

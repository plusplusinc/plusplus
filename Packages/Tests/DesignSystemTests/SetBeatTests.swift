import SwiftUI
import Testing
@testable import DesignSystem

/// The current node's beat as a set logs that stays on its exercise: the values it is drawn at,
/// held or not, and the animations it runs between them from wherever it is drawn.
@Suite("Set beat")
struct SetBeatTests {
    @Test("As a set logs, the node shrinks to half and grays over 0.2 s, and rests so")
    func holds() {
        let held = SetBeat(held: true)
        #expect(held.scale == 0.5)
        #expect(held.gray == 1)
        #expect(SetBeat.scaleAnimation(held: true) == .easeInOut(duration: 0.2))
        #expect(SetBeat.grayAnimation(held: true) == .easeInOut(duration: 0.2))
    }

    @Test("Let go, it pops back to full size on a bouncy spring, green again in 0.12 s")
    func pops() {
        let shown = SetBeat(held: false)
        #expect(shown.scale == 1)
        #expect(shown.gray == 0)
        #expect(SetBeat.scaleAnimation(held: false) == .bouncy)
        #expect(SetBeat.grayAnimation(held: false) == .easeInOut(duration: 0.12))
    }
}

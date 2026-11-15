import SwiftUI
import Testing
@testable import DesignSystem

/// With Reduce Motion, a value row's value and its ruler change without motion: the digits
/// crossfade rather than roll, and the ruler goes to a value set from outside (a − / + key, an
/// Auto switch) at once rather than sliding. Without it, both move.
@MainActor
@Suite("Value row with Reduce Motion")
struct ValueReduceMotionTests {
    @Test("With Reduce Motion a value crossfades and its ruler doesn't slide")
    func valueAndRulerHoldStill() {
        #expect(ValueText.transition(rolling: 27.5, reduceMotion: true) == .opacity)
        #expect(ValueText.transition(rolling: nil, reduceMotion: true) == .opacity)
        #expect(ValueRuler.slide(reduceMotion: true) == nil)
    }

    @Test("Without Reduce Motion a value rolls and its ruler slides")
    func valueAndRulerMove() {
        #expect(ValueText.transition(rolling: 27.5, reduceMotion: false) == .numericText(value: 27.5))
        #expect(ValueRuler.slide(reduceMotion: false) != nil)
    }
}

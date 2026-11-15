import SwiftUI
import Testing
@testable import DesignSystem

/// With Reduce Motion, a value row's ruler goes to a value set from outside (a − / + key, an Auto
/// switch) at once rather than sliding; without it, it slides. That the value itself crossfades
/// at its places, nothing in it sliding, shows only in rendered frames between a change's
/// start and end, which no test here reads.
@MainActor
@Suite("Value row with Reduce Motion")
struct ValueReduceMotionTests {
    @Test("With Reduce Motion a ruler goes to a value at once")
    func rulerHoldsStill() {
        #expect(ValueRuler.slide(reduceMotion: true) == nil)
    }

    @Test("Without Reduce Motion a ruler slides to a value")
    func rulerSlides() {
        #expect(ValueRuler.slide(reduceMotion: false) != nil)
    }
}

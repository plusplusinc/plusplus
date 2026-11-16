import SwiftUI
import Testing
@testable import DesignSystem

/// With Reduce Motion, a value row's value and its ruler change without motion: text that
/// changes with its number crossfades rather than rolls, a new number is a new view crossfaded
/// in (`ValueChange`), and the ruler goes to a value set from outside (a − / + key, an Auto
/// switch) at once rather than sliding. Without it, both move. That nothing in the value slides
/// shows only in rendered frames between a change's start and end, which no test here reads.
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
        let rolling = ValueText.transition(rolling: 27.5, reduceMotion: false)
        #expect(rolling == .numericText(value: 27.5))
        #expect(ValueRuler.slide(reduceMotion: false) != nil)
    }

    @Test("A row's value changes with its number, not with its text's shape as it opens")
    func valueChangesWithItsNumber() {
        let shut = ValueChange(number: 30, value: "30s")
        #expect(ValueChange(number: 30, value: "0m\u{00A0}30s") == shut)
        #expect(ValueChange(number: 35, value: "35s") != shut)
        #expect(ValueChange(number: nil, value: "3") != ValueChange(number: nil, value: "4"))
    }
}

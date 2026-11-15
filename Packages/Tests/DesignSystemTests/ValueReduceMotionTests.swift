import SwiftUI
import Testing
@testable import DesignSystem

/// With Reduce Motion, a value row's value and its ruler change without motion: the value's line
/// lays out a new value at once (the value crossfading as a new view), and the ruler goes to a
/// value set from outside (a − / + key, an Auto switch) at once rather than sliding. Without it,
/// both move in the change's own animation.
@MainActor
@Suite("Value row with Reduce Motion")
struct ValueReduceMotionTests {
    private typealias Row = ValueRow<EmptyView, EmptyView>

    @Test("With Reduce Motion a value's line and its ruler take a new value at once")
    func valueAndRulerHoldStill() {
        let change = ValueRow.change
        #expect(Row.layoutAnimation(change, reduceMotion: true) == nil)
        #expect(ValueRuler.slide(reduceMotion: true) == nil)
    }

    @Test(
        "Without Reduce Motion a value's line moves in the change's animation and its ruler slides",
    )
    func valueAndRulerMove() {
        let change = ValueRow.change
        #expect(Row.layoutAnimation(change, reduceMotion: false) == change)
        #expect(ValueRuler.slide(reduceMotion: false) != nil)
    }
}

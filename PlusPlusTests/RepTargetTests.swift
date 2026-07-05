import Testing
@testable import PlusPlus

@Suite("RepTarget")
struct RepTargetTests {
    @Test("Nil lower means empty target")
    func emptyTarget() {
        let target = RepTarget(lower: nil, upper: 20)
        #expect(target.lower == nil)
        #expect(target.upper == nil)
        #expect(target.display == "—")
    }

    @Test("Upper must exceed lower to form a range")
    func rangeNormalization() {
        #expect(RepTarget(lower: 15, upper: 20).upper == 20)
        #expect(RepTarget(lower: 15, upper: 15).upper == nil)
        #expect(RepTarget(lower: 15, upper: 10).upper == nil)
        #expect(RepTarget(lower: 15, upper: nil).upper == nil)
    }

    @Test("Values clamp to 1...100")
    func clamping() {
        #expect(RepTarget(lower: 0).lower == 1)
        #expect(RepTarget(lower: 500).lower == 100)
        #expect(RepTarget(lower: 90, upper: 500).upper == 100)
    }

    @Test("Display formats singles and ranges")
    func display() {
        #expect(RepTarget(lower: 10).display == "10")
        #expect(RepTarget(lower: 15, upper: 20).display == "15–20")
    }

    @Test("Stepping shifts the whole range, preserving the span")
    func steppingShiftsRange() {
        let range = RepTarget(lower: 15, upper: 20)
        #expect(range.incremented() == RepTarget(lower: 16, upper: 21))
        #expect(range.decremented() == RepTarget(lower: 14, upper: 19))

        let single = RepTarget(lower: 10)
        #expect(single.incremented() == RepTarget(lower: 11))
    }

    @Test("Stepping from empty lands on the default")
    func steppingFromEmpty() {
        let empty = RepTarget(lower: nil)
        #expect(empty.incremented() == RepTarget(lower: RepTarget.defaultReps))
        #expect(empty.decremented() == RepTarget(lower: RepTarget.defaultReps))
    }

    @Test("Range collapses to a single value at the top of the scale")
    func collapseAtBounds() {
        let nearTop = RepTarget(lower: 99, upper: 100)
        let bumped = nearTop.incremented()
        #expect(bumped.lower == 100)
        #expect(bumped.upper == nil)
    }
}

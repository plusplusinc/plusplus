import Foundation
import Testing
@testable import WorkoutStore

extension WorkoutPhaseTests {
    @Test("A skipped rest keeps the time it had left through its way out, and no longer")
    func skippedRestHoldsItsTime() {
        var phase = WorkoutPhase.running
        let skippedWithNoRest = phase.skipRest(left: 42)
        #expect(!skippedWithNoRest)
        phase.log(Self.logged, leadingTo: Self.down, rests: true, moves: true)
        phase.show()
        phase.landRest()
        #expect(phase.resting?.skippedLeft == nil)
        // Skipped before the move into it is over, it holds until its end can play.
        phase.skipRest(left: 42)
        let endedEarly = phase.endRest()
        #expect(!endedEarly)
        #expect(phase.resting?.skippedLeft == 42)
        phase.settleRest()
        phase.endRest()
        #expect(phase.move?.skippedLeft == 42)
        // The next rest starts unskipped.
        phase = .running
        phase.log(Self.logged, leadingTo: Self.down, rests: true, moves: true)
        #expect(phase.resting?.skippedLeft == nil)
        phase.show()
        phase.landRest()
        phase.settleRest()
        phase.endRest()
        #expect(phase.move?.isFromRest == true)
        #expect(phase.move?.skippedLeft == nil)
    }

    @Test("Between two sets, a skipped rest keeps its time as it swaps back, with no second skip")
    func skippedRestBetweenSetsHoldsItsTime() {
        var phase = WorkoutPhase.running
        phase.log(Self.logged, leadingTo: .nextSet, rests: true, moves: true)
        phase.show()
        phase.settleRest()
        phase.skipRest(left: 42)
        phase.endRest()
        #expect(phase.resting?.beat == .returning)
        #expect(phase.resting?.skippedLeft == 42)
        let skippedAgain = phase.skipRest(left: 7)
        #expect(!skippedAgain)
        #expect(phase.resting?.skippedLeft == 42)
    }
}

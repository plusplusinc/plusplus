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

    @Test("A skip's hold times only its own rest: the next rest, a later workout's too, its own")
    func skipLeaveStaysWithItsRest() {
        let rest = WorkoutRest(after: Self.logged, next: Self.logged, length: 30, startClock: 100)
        var phase = WorkoutPhase.running
        phase.log(Self.logged, leadingTo: .nextSet, rests: true, moves: true)
        phase.show()
        phase.settleRest()
        // Skipped at 104, with no count stored to time the move: the phase's hold times it.
        phase.skipRest(left: 26, leave: 104.25)
        #expect(phase.leaveClock(of: rest) == 104.25)
        phase.endRest()
        phase.settleReturn(on: nil)
        // The next rest, or the first of a workout started again on the same screen, with a
        // clock that starts again from 0: it moves on as its own 0:00 has held.
        for next in [phase, .running] {
            var phase = next
            phase.log(Self.logged, leadingTo: .nextSet, rests: true, moves: true)
            #expect(phase.resting != nil)
            #expect(phase.resting?.skipLeave == nil)
            let later = WorkoutRest(
                after: Self.logged,
                next: Self.logged,
                length: 30,
                startClock: 5,
            )
            #expect(phase.leaveClock(of: later) == later.leaveClock)
        }
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

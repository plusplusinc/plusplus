import Foundation
import Testing
@testable import DesignSystem

/// Which changes of a count's figure roll and which come at once (`RestBlock.rolls`), and when a
/// rest between sets lets its figure turn (`SetRest.turnsFigure`).
struct CountRollTests {
    private static let running = RestBlock(stage: .open, length: 60, ends: .now + 30)
    private static let held = RestBlock(stage: .open, length: 60, ends: .now + 30, pausedLeft: 30)

    @Test("Each second going by rolls while the count runs, and its last, to 0:00, does not")
    func tick() {
        #expect(Self.running.rolls(on: .tick, to: 9))
        #expect(Self.running.rolls(on: .tick, to: 0.4))
        #expect(!Self.running.rolls(on: .tick, to: 0))
    }

    @Test("A held count, paused, ended, or leaving, never rolls a tick")
    func heldTick() {
        #expect(!Self.held.rolls(on: .tick, to: 30))
        // Leaving, a wait is held where it stood.
        #expect(!Self.running.holding(at: .now).rolls(on: .tick, to: 29))
        #expect(!RestBlock.closed.rolls(on: .tick, to: 30))
    }

    @Test("+15 s rolls an open count, paused included, but not a cut to 0:00")
    func moved() {
        #expect(Self.running.rolls(on: .moved, to: 45))
        #expect(Self.held.rolls(on: .moved, to: 45))
        #expect(!Self.running.rolls(on: .moved, to: 0))
        #expect(!RestBlock.closed.rolls(on: .moved, to: 45))
    }

    @Test("A new figure, any roll in flight dropped, held as it goes and on Skip rest, not paused")
    func cut() {
        let running = Self.running.figureKey(skips: 0)
        // Held by End, by a timed set's log, or after End as the room closes.
        #expect(Self.held.figureKey(skips: 0) != running)
        let closing = RestBlock(stage: .none, length: 60, pausedLeft: 30)
        #expect(closing.figureKey(skips: 0) != running)
        // Skip rest, in the tap's own change.
        #expect(Self.running.figureKey(skips: 1) != running)
        let paused = RestBlock(
            stage: .open,
            length: 60,
            ends: .now + 30,
            pausedLeft: 30,
            isPaused: true,
        )
        #expect(paused.figureKey(skips: 0) == running)
        // Leaving while paused, a wait is held by its going.
        #expect(paused.holding(at: .now).figureKey(skips: 0) != running)
        // A rest between sets paused keeps its roll, as a rest between exercises does.
        let pausedBetweenSets = SetRest(
            isRunning: true,
            length: 60,
            pausedLeft: 30,
            turns: true,
            isPaused: true,
        )
        #expect(pausedBetweenSets.block.figureKey(skips: 0) == running)
    }

    @Test("A count that runs out keeps its figure through 0:00 and the swap back")
    func runOut() {
        let running = SetRest(isRunning: true, length: 60, ends: .now + 1, turns: true)
        let over = SetRest(isRunning: false, length: 60, ends: .now, isOver: true)
        #expect(over.block.figureKey(skips: 0) == running.block.figureKey(skips: 0))
        // Between exercises its room closes, and leaving at 0:00, it holds nothing.
        #expect(RestBlock.closed.figureKey(skips: 0) == Self.running.figureKey(skips: 0))
        let ran = RestBlock(stage: .open, length: 60, ends: .now - 1)
        #expect(ran.holding(at: .now).figureKey(skips: 0) == Self.running.figureKey(skips: 0))
        // After a skip, the count it put in stays through the swap back.
        #expect(over.block.figureKey(skips: 1) == running.block.figureKey(skips: 1))
    }

    @Test("A rest between sets turns its figure once up and as it goes, never as it comes in")
    func restBetweenSets() {
        let coming = SetRest(isRunning: true, length: 60, turns: false)
        let up = SetRest(isRunning: true, length: 60, turns: true)
        // Skip rest cuts the count to 0:00 in the change that sends it back.
        let going = SetRest(isRunning: false, length: 60, isOver: true, turns: false)
        #expect(!coming.turnsFigure)
        #expect(up.turnsFigure)
        #expect(going.turnsFigure)
    }
}

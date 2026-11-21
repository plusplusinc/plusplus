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

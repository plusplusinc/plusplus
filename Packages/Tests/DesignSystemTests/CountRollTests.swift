import Foundation
import Testing
@testable import DesignSystem

/// Which changes of a count's figure roll and which come at once (`RestBlock.rolls`).
struct CountRollTests {
    private static let running = RestBlock(stage: .open, length: 60, ends: .now + 30)
    private static let held = RestBlock(stage: .open, length: 60, ends: .now + 30, pausedLeft: 30)

    @Test("Each second going by rolls while the count runs, and its last, to 0:00, does not")
    func tick() {
        #expect(Self.running.rolls(on: .tick, to: 9, turns: true))
        #expect(Self.running.rolls(on: .tick, to: 0.4, turns: true))
        #expect(!Self.running.rolls(on: .tick, to: 0, turns: true))
    }

    @Test("A held count, paused, ended, or leaving, never rolls a tick")
    func heldTick() {
        #expect(!Self.held.rolls(on: .tick, to: 30, turns: true))
        // Leaving, a wait is held where it stood.
        #expect(!Self.running.holding(at: .now).rolls(on: .tick, to: 29, turns: true))
        #expect(!RestBlock.closed.rolls(on: .tick, to: 30, turns: true))
    }

    @Test("+15 s rolls an open count, paused included, but not a cut to 0:00")
    func moved() {
        #expect(Self.running.rolls(on: .moved, to: 45, turns: true))
        #expect(Self.held.rolls(on: .moved, to: 45, turns: true))
        #expect(!Self.running.rolls(on: .moved, to: 0, turns: true))
        #expect(!RestBlock.closed.rolls(on: .moved, to: 45, turns: true))
    }

    @Test("With turns off, as with Reduce Motion, nothing rolls")
    func reduceMotion() {
        #expect(!Self.running.rolls(on: .tick, to: 9, turns: false))
        #expect(!Self.running.rolls(on: .moved, to: 45, turns: false))
    }
}

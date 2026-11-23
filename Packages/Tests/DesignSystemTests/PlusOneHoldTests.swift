import CoreGraphics
import Testing
@testable import DesignSystem

/// Where the key's +1 plays as the key moves under it, from plain values.
@Suite("Plus one hold")
struct PlusOneHoldTests {
    private typealias Input = PlusOneHold.Input

    private let resting = CGRect(x: 21, y: 700, width: 351, height: 56)
    private let sliding = CGRect(x: 21, y: 760, width: 351, height: 56)

    @Test("Between bursts the +1 is at the key")
    func betweenBursts() {
        let hold = PlusOneHold()
        #expect(hold.spot(for: resting) == resting)
        #expect(hold.spot(for: nil) == nil)
    }

    @Test("A burst plays on where the key was as the key slides away and goes")
    func outlastsTheKey() {
        var hold = PlusOneHold()
        // The update that logs the set already has the key moving.
        hold.follow(from: Input(trigger: 0, key: resting), to: Input(trigger: 1, key: sliding))
        hold.follow(from: Input(trigger: 1, key: sliding), to: Input(trigger: 1, key: nil))
        #expect(hold.spot(for: sliding) == resting)
        #expect(hold.spot(for: nil) == resting)
    }

    @Test("A burst that follows another before its end stays where the first began")
    func burstsInARow() {
        var hold = PlusOneHold()
        hold.follow(from: Input(trigger: 0, key: resting), to: Input(trigger: 1, key: resting))
        hold.follow(from: Input(trigger: 1, key: sliding), to: Input(trigger: 2, key: sliding))
        #expect(hold.spot(for: sliding) == resting)
    }

    @Test("Once a burst is over, the next one starts from where the key is then")
    func afterABurst() {
        var hold = PlusOneHold()
        hold.follow(from: Input(trigger: 0, key: resting), to: Input(trigger: 1, key: sliding))
        hold.release()
        #expect(hold.spot(for: sliding) == sliding)
    }
}

import CoreGraphics
import Testing
@testable import DesignSystem

/// Where the key's +1 plays as the key moves under it, from plain values: each `spot` is one
/// draw of the bar.
@Suite("Plus one hold")
struct PlusOneHoldTests {
    private let resting = CGRect(x: 21, y: 700, width: 351, height: 56)
    private let sliding = CGRect(x: 21, y: 760, width: 351, height: 56)

    @Test("Between bursts the +1 is at the key")
    func betweenBursts() {
        var hold = PlusOneHold()
        #expect(hold.spot(trigger: 0, key: resting) == resting)
        #expect(hold.spot(trigger: 0, key: sliding) == sliding)
        #expect(hold.spot(trigger: 0, key: nil) == nil)
    }

    @Test("A burst plays on where the key was, from the draw that logs, as the key slides and goes")
    func outlastsTheKey() {
        var hold = PlusOneHold()
        _ = hold.spot(trigger: 0, key: resting)
        // The update that logs the set already has the key moving.
        #expect(hold.spot(trigger: 1, key: sliding) == resting)
        #expect(hold.spot(trigger: 1, key: nil) == resting)
    }

    @Test("A burst as the key leaves in the same update plays where the key was")
    func keyGoneWithTheLog() {
        var hold = PlusOneHold()
        _ = hold.spot(trigger: 0, key: resting)
        #expect(hold.spot(trigger: 1, key: nil) == resting)
    }

    @Test("A burst that follows another before its end stays where the first began")
    func burstsInARow() {
        var hold = PlusOneHold()
        _ = hold.spot(trigger: 0, key: resting)
        _ = hold.spot(trigger: 1, key: resting)
        _ = hold.spot(trigger: 1, key: sliding)
        #expect(hold.spot(trigger: 2, key: sliding) == resting)
    }

    @Test("Once a burst is over, the next one starts from where the key is then")
    func afterABurst() {
        var hold = PlusOneHold()
        _ = hold.spot(trigger: 0, key: resting)
        _ = hold.spot(trigger: 1, key: sliding)
        hold.release()
        #expect(hold.spot(trigger: 1, key: sliding) == sliding)
        #expect(hold.spot(trigger: 2, key: resting) == sliding)
    }

    @Test("A burst that began with no key stays unseen over a key that comes in before its end")
    func noKeyAtTheLog() {
        var hold = PlusOneHold()
        _ = hold.spot(trigger: 0, key: nil)
        #expect(hold.spot(trigger: 1, key: nil) == nil)
        #expect(hold.spot(trigger: 1, key: resting) == nil)
        hold.release()
        #expect(hold.spot(trigger: 1, key: resting) == resting)
    }
}

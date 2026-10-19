import Foundation
import Testing
@testable import DesignSystem

/// The room above a rail: the list scrolls by each frame of it, so the rail and the card on it
/// stay still on the screen, and it moves smoothly to whatever size is asked.
@Suite("Rail room")
struct RailRoomTests {
    @Test("Room the list can scroll for leaves the rail where it is")
    func scrolledInFull() {
        let made = RailDrag.roomScroll(from: 40, grown: 6, end: 300)
        #expect(made.to == 46)
        #expect(made.railMoves == 0)
        let closed = RailDrag.roomScroll(from: 46, grown: -6, end: 300)
        #expect(closed.to == 40)
        #expect(closed.railMoves == 0)
    }

    @Test("Room past the list's end moves the rail by what the scroll falls short of")
    func pastTheEnd() {
        let made = RailDrag.roomScroll(from: 98, grown: 6, end: 100)
        #expect(made.to == 100)
        #expect(made.railMoves == 4)
    }

    @Test("Room closing at the list's top moves the rail up by what it can't scroll back")
    func atTheTop() {
        let closed = RailDrag.roomScroll(from: 2, grown: -6, end: 100)
        #expect(closed.to == 0)
        #expect(closed.railMoves == -4)
    }

    @Test("A list already past its end isn't pulled back by room")
    func pastEndStays() {
        let made = RailDrag.roomScroll(from: 120, grown: 0, end: 100)
        #expect(made.to == 120)
        #expect(made.railMoves == 0)
    }

    @Test("The room sets off from where it is and arrives where asked")
    func arrives() {
        var move = RailRoomMove()
        #expect(move.value == 0)
        move.aim(at: 30)
        #expect(!move.isSettled)
        #expect(move.value == 0)
        var last: CGFloat = 0
        for _ in 0 ..< 60 {
            let value = move.advance(by: 1.0 / 60)
            #expect(value >= last - 0.5)
            last = value
        }
        #expect(move.isSettled)
        #expect(move.value == 30)
    }

    @Test("A new size asked mid-move carries on from where the room is, with no jump")
    func retargets() {
        var move = RailRoomMove()
        move.aim(at: 30)
        let before = move.advance(by: 0.05)
        move.aim(at: 0)
        #expect(abs(move.value - before) < 0.001)
        // Still moving up a frame later, as it was: it turns around, it doesn't snap.
        #expect(move.advance(by: 1.0 / 120) > before - 0.5)
    }

    @Test("Jumping arrives at once")
    func jumps() {
        var move = RailRoomMove()
        move.aim(at: 30)
        move.jump(to: 12)
        #expect(move.isSettled)
        #expect(move.value == 12)
    }
}

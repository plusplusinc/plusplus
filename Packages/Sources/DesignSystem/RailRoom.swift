import SwiftUI

// Room above a rail, made by scrolling the list as the rail pads its top, so the rail, and a card
// held on it, stay still on the screen while what is above the rail moves up.

nonisolated extension RailDrag {
    /// The room above the rail opening or closing: as quick as the rows moving aside.
    static let roomSpring = Spring.snappy(duration: 0.2)

    /// One frame of the room above the rail growing by `grown`, the list scrolled to `y`: the
    /// list scrolls by as much, to `to`, never above its top and past `end` only where it is
    /// already, and the rail moves down the screen, `railMoves`, by whatever the scroll fell
    /// short of. Scrolled in full, the rail stays where it is.
    static func roomScroll(
        from y: CGFloat,
        grown: CGFloat,
        end: CGFloat,
    ) -> (to: CGFloat, railMoves: CGFloat) {
        let to = min(max(y + grown, 0), max(end, y))
        return (to, grown - (to - y))
    }
}

/// The room above a rail moving toward the size asked of it, a frame at a time, on
/// `RailDrag.roomSpring`: from where it is, at the speed it has, so a new size asked mid-move
/// carries on with no jump.
nonisolated struct RailRoomMove {
    private(set) var target: CGFloat = 0
    private var from: CGFloat = 0
    private var velocity: CGFloat = 0
    /// Time since it set off for `target`.
    private var elapsed: TimeInterval = .infinity
    private let spring = RailDrag.roomSpring

    /// Whether it has arrived.
    var isSettled: Bool {
        elapsed >= spring.settlingDuration
    }

    /// The room now.
    var value: CGFloat {
        isSettled ? target
            : from + spring.value(target: target - from, initialVelocity: velocity, time: elapsed)
    }

    private var speed: CGFloat {
        isSettled ? 0
            : spring.velocity(target: target - from, initialVelocity: velocity, time: elapsed)
    }

    /// Sets off for `newTarget`, from where it is.
    mutating func aim(at newTarget: CGFloat) {
        guard newTarget != target else { return }
        (from, velocity) = (value, speed)
        target = newTarget
        elapsed = 0
    }

    /// Moves on by `seconds`, returning the room then.
    mutating func advance(by seconds: TimeInterval) -> CGFloat {
        elapsed += seconds
        return value
    }

    /// Arrives at `newTarget` at once.
    mutating func jump(to newTarget: CGFloat) {
        target = newTarget
        elapsed = .infinity
    }
}

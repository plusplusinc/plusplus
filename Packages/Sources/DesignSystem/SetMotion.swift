import SwiftUI

/// Every timing in logging a set and moving on, in one place, so a tweak tried on the phone is one
/// line and a rebuild.
///
/// Moving to another exercise is a sequence of three beats, each starting a little before the
/// last ends, so it never pauses: the current exercise shrinks back to a resting row (`shrink`);
/// a green pulse travels along the rail from its node to the next one's, the list scrolling the
/// next row up under the bar with it (`travel`); and the next row grows into the current exercise
/// as the pulse lands (`grow`). About 0.8 s in all.
public enum SetMotion {
    // MARK: The slide

    /// How far along the track the key has to go to log the set: past it, the arrow turns to a
    /// check, the fill turns purple, and a haptic plays; a release logs. Slid back under it, all
    /// three go back.
    static let commit = 2.0 / 3
    /// A key let go short of `commit` springing back to the start.
    static let springBack = 0.35
    /// A key let go past `commit` finishing its slide to the track's end.
    static let finish = 0.18
    /// The key resting at the end while the progress line rolls to the next set.
    static let rest = 0.8
    /// The key fading out at the end, then in again at the start.
    static let fadeOut = 0.15
    static let fadeIn = 0.2
    /// The fill behind the key turning purple at `commit`, or neutral again under it.
    static let fillTurn = 0.12

    // MARK: Within one exercise

    /// "Set 2 of 3" rolling up and out as "Set 3 of 3" rolls up and in, once the set logs; the
    /// side word, "Left" to "Right", rolls with it.
    public static let roll = 0.3

    // MARK: Moving on to another exercise

    /// The current exercise shrinking back to a resting row, its numbers and slide fading.
    public static let shrink = 0.2
    /// How long before the shrink ends that the pulse sets off.
    public static let shrinkOverlap = 0.05
    /// The pulse traveling from the current node to the next, the list scrolling with it.
    public nonisolated static let travel = 0.4
    /// The pulse's speed at its start, against its average: an ease-in that is moving from the
    /// first frame, so it never looks stuck, and fastest as it lands.
    nonisolated static let travelRunningStart = 0.35
    /// After the pulse lands, how long its stretch takes to collapse into the node.
    public nonisolated static let collapse = 0.06
    /// How long before the pulse lands that the next exercise starts to grow.
    public static let growLead = 0.05
    /// The next exercise growing into the current one, its numbers and slide coming in.
    public static let grow = 0.25
    /// At a superset round's end, how long after the first member starts to grow that "Round 2
    /// of 3" rolls to "Round 3 of 3", taking `roll`.
    public static let roundRoll = 0.12
    /// After the last planned set, the list settling on its end, the Finish row in view.
    public static let settle = 0.35
    /// How far the scroll trails the pulse, as a share of `travel`: 0 keeps the next node exactly
    /// under the pulse's front, so the pulse holds still on the screen as the rail slides under
    /// it; more lets it run ahead on the screen and the list catch up as it lands. Moving up a
    /// superset's loop at a round's end, the scroll leads by as much instead, so the first member
    /// comes into view and the pulse lands on it.
    public static let scrollLag = 0.35

    /// When the pulse sets off, from the slide's log.
    public static var travelStart: Double {
        shrink - shrinkOverlap
    }

    /// When the next exercise starts to grow, from the slide's log.
    public static var growStart: Double {
        travelStart + travel - growLead
    }

    /// The whole move, from the slide's log to the next exercise grown.
    public static var move: Double {
        growStart + grow
    }

    /// The list's scroll to the next exercise, as the pulse travels: on the pulse's own curve,
    /// trailing it going down, or leading it going `up` the loop, and done as it lands.
    public static func scroll(up: Bool) -> Animation {
        let duration = travel * (1 - scrollLag)
        let delay = up ? 0 : travel * scrollLag
        return Animation(TravelArc(duration: duration)).delay(travelStart + delay)
    }

    /// Where along the travel, from 0 to 1, the pulse is a share `time` of the way through it: an
    /// ease-in from a running start, a quadratic, so it gathers speed without hanging back.
    nonisolated static func distance(at time: Double) -> Double {
        travelRunningStart * time + (1 - travelRunningStart) * time * time
    }

    /// The pulse's speed at a share `time` of its travel, against its average.
    nonisolated static func speed(at time: Double) -> Double {
        travelRunningStart + 2 * (1 - travelRunningStart) * time
    }
}

/// The travel as an animation: `SetMotion.distance(at:)` over `duration`, computed frame by frame,
/// so the scroll moves on the pulse's own curve.
struct TravelArc: CustomAnimation {
    let duration: TimeInterval

    func animate<V: VectorArithmetic>(
        value: V,
        time: TimeInterval,
        context _: inout AnimationContext<V>,
    ) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: SetMotion.distance(at: time / duration))
    }
}

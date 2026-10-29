import SwiftUI

/// Every timing in logging a set and moving on, in one place, so a tweak tried on the phone is one
/// line and a rebuild.
///
/// Moving to another exercise is one motion from the slide's log, about 0.7 s:
/// - **Leave** (0 to 0.14 s): what the current exercise grew to show goes, bottom first, each part
///   fading as it drops a few points: the slide, the numbers, then the equipment and the progress
///   line.
/// - **Shift** (`shiftStart`, 0.04 to 0.69 s): on one curve, the row shrinks back to a resting row
///   as the next row grows into the current exercise and the list scrolls it up under the bar,
///   so what lies between and below moves up once, with the scroll, never back down. A green
///   pulse shoots along the rail from the node left to the next one's and lands as the next row
///   comes to rest under the bar, a dot on the node until the node lights.
/// - **Arrive**: the next row's parts come in top first as it has room for them, each fading as
///   it rises a few points: the progress line, the equipment, the numbers, the slide.
public enum SetMotion {
    // MARK: The slide

    /// How far along the track the key has to go to log the set: past it, the arrow turns to a
    /// check and a haptic plays; a release logs. Slid back under, both go back.
    static let commit = 2.0 / 3
    /// How quickly a key let go slows, as UIKit's deceleration rates go: kept a share of its
    /// speed each millisecond. At 0.994 it coasts about a sixth of a second's worth of its speed,
    /// so from a quarter of the way, a flick at about 750 pt/s on a 300 pt travel carries it past
    /// `commit`, and a slow drag, 200 pt/s, about 33 pt.
    static let coastRate = 0.994
    /// A key let go short of `commit` springing back to the start.
    static let springBack = 0.35
    /// A key let go past `commit` finishing its slide to the track's end.
    static let finish = 0.18
    /// The key resting at the end while the progress line rolls to the next set.
    static let rest = 0.8
    /// The key fading out at the end, then in again at the start.
    static let fadeOut = 0.15
    static let fadeIn = 0.2

    // MARK: Within one exercise

    /// "Set 2 of 3" rolling up and out as "Set 3 of 3" rolls up and in, once the set logs; the
    /// side word, "Left" to "Right", rolls with it.
    public static let roll = 0.3

    // MARK: Moving on to another exercise: leave

    /// Each part of the current exercise fading out as it goes.
    public static let leaveFade = 0.09
    /// How far each part drops as it fades out.
    static let leaveDrop: CGFloat = 6
    /// How long after the part below it each part starts to go, bottom first.
    static let leaveStagger = 0.025

    /// When `part` starts to go, from the slide's log.
    static func leaveDelay(_ part: Part) -> Double {
        switch part {
        case .slide: 0
        case .figures: leaveStagger
        case .equipment, .progress: leaveStagger * 2
        }
    }

    // MARK: Shift

    /// When the row starts to shrink, the next to grow, and the list to scroll, from the slide's
    /// log: as the slide goes, so nothing waits; the row's bottom cuts off whatever is still
    /// going as it closes.
    public static let shiftStart = 0.04
    /// The shift, the row shrinking as the next grows and the list scrolls, on one curve, so the
    /// rows below move as one.
    public nonisolated static let shift = 0.65

    /// The shift's curve: under way gently, as the parts go, and easing to a stop with no
    /// overshoot. Shared by both rows' heights, the names' sizes, and the list's scroll.
    public static var shifting: Animation {
        .timingCurve(0.42, 0, 0.2, 1, duration: shift).delay(shiftStart)
    }

    /// When the pulse sets off, from the slide's log: as the slide starts to go.
    nonisolated static let travelStart = 0.08
    /// The pulse shooting from the node left to the next one's, landing as the shift brings the
    /// next row to rest under the bar.
    nonisolated static let travel = 0.48
    /// The pulse's speed as it lands, against its average: an ease-out that shoots off and still
    /// hits the node moving, never creeping into it.
    nonisolated static let travelLanding = 0.6
    /// After the pulse lands, how long its stretch takes to collapse into a dot on the node.
    nonisolated static let collapse = 0.06
    /// How long after the next row's node lights that the pulse's dot goes, under the green node
    /// by then.
    nonisolated static let dotHold = 0.06

    /// When the next row's node lights, from the slide's log: as the pulse's dot settles on it.
    public static var landing: Double {
        travelStart + travel + collapse
    }

    /// The detail line, back on the row closing, fading in once the progress line has gone and
    /// the row is well on its way to a resting row.
    static var detailIn: Animation {
        .easeOut(duration: 0.15).delay(0.15)
    }

    /// The detail line on the next row going as its name starts to grow.
    static let detailOut = Animation.easeIn(duration: 0.06)

    // MARK: Arrive

    /// Each part of the next exercise fading in as it rises into place.
    static let arriveFade = 0.16
    /// How far each part rises as it comes in.
    static let arriveRise: CGFloat = 8

    /// When `part` starts to come in, from the slide's log: top first, each once the row has
    /// grown enough to hold it, the progress line once the detail line has gone (`detailOut`).
    static func arriveDelay(_ part: Part) -> Double {
        switch part {
        case .progress: 0.2
        case .equipment: 0.26
        case .figures: 0.32
        case .slide: 0.4
        }
    }

    // MARK: After the last set

    /// After the last planned set, the Finish row fading in, from the log: once the last row is
    /// mostly closed, so it never shows over the slide going.
    public static let finishIn = Animation.easeOut(duration: 0.2).delay(0.26)

    // MARK: The timeline

    /// The whole move, from the slide's log to the shift's end, the next exercise's last part in
    /// place and the pulse's dot gone.
    public static var move: Double {
        max(shiftStart + shift, arriveDelay(.slide) + arriveFade, landing + dotHold)
    }

    /// The current exercise's parts under its name, which leave and arrive in turn.
    enum Part {
        case progress
        case equipment
        case figures
        case slide
    }

    /// Where along the travel, from 0 to 1, the pulse is a share `time` of the way through it: a
    /// quadratic ease-out, fastest as it sets off and landing at `travelLanding`.
    nonisolated static func distance(at time: Double) -> Double {
        (2 - travelLanding) * time - (1 - travelLanding) * time * time
    }

    /// The pulse's speed at a share `time` of its travel, against its average.
    nonisolated static func speed(at time: Double) -> Double {
        (2 - travelLanding) - 2 * (1 - travelLanding) * time
    }
}

import SwiftUI

/// Every timing in logging a set and moving on, in one place, so a tweak tried on the phone is one
/// line and a rebuild.
///
/// Moving to another exercise is one timeline from the slide's log, about 0.8 s, in three beats
/// that overlap so it never stalls:
/// - **Leave** (`leaveStart`, 0 to 0.14 s): what the current exercise grew to show goes before
///   its row closes, bottom first, each part fading as it drops a few points: the slide, the
///   numbers, then the equipment and the progress line.
/// - **Close** (`closeStart`, 0.1 to 0.52 s): on one curve, the row shrinks back to a resting row,
///   its name shrinking with it, as the list scrolls the next row up under the bar and the next
///   row's name grows to the current exercise's size. Ahead of it, from 0.06 s, a green pulse
///   shoots along the rail from the node left to the next one's, leading the eye there, and lands
///   at 0.34 s, a dot that rides the node up under the bar until the row opens.
/// - **Open** (`openStart`, 0.49 to 0.78 s): the next row opens to its content's height, with no
///   overshoot, and once it has room its parts come in top first, each fading as it rises a few
///   points: the progress line, the equipment, the numbers, the slide.
public enum SetMotion {
    // MARK: The slide

    /// How far along the track the key has to go to log the set: past it, the arrow turns to a
    /// check and a haptic plays; a release logs. Slid back under, both go back.
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

    // MARK: Within one exercise

    /// "Set 2 of 3" rolling up and out as "Set 3 of 3" rolls up and in, once the set logs; the
    /// side word, "Left" to "Right", rolls with it.
    public static let roll = 0.3

    // MARK: Moving on to another exercise: leave

    /// Each part of the current exercise fading out as it goes.
    public static let leaveFade = 0.09
    /// How far each part drops as it fades out.
    public static let leaveDrop: CGFloat = 6
    /// How long after the part below it each part starts to go, bottom first.
    public static let leaveStagger = 0.025

    /// When `part` starts to go, from the slide's log.
    public static func leaveDelay(_ part: Part) -> Double {
        switch part {
        case .slide: 0
        case .figures: leaveStagger
        case .equipment, .progress: leaveStagger * 2
        }
    }

    // MARK: Close

    /// When the row starts to close and the list to scroll, from the slide's log: as the last
    /// parts finish going, low enough by then that the rows rising below never pass under one.
    public static let closeStart = 0.1
    /// The row closing and the list scrolling the next row under the bar, on one curve, so the
    /// rows below move as one.
    public nonisolated static let close = 0.42

    /// The close's curve: under way gently, as the last parts go, and easing to a stop with no
    /// overshoot. Shared by the row's shrink, the names' sizes, and the list's scroll.
    public static var closing: Animation {
        .timingCurve(0.42, 0, 0.2, 1, duration: close)
    }

    /// When the pulse sets off, from the slide's log: as the slide starts to go, ahead of the
    /// close, so it leads.
    public static let travelStart = 0.06
    /// The pulse shooting from the node left to the next one's.
    public nonisolated static let travel = 0.28
    /// The pulse's speed as it lands, against its average: an ease-out that shoots off and still
    /// hits the node moving, never creeping into it.
    nonisolated static let travelLanding = 0.6
    /// After the pulse lands, how long its stretch takes to collapse into a dot on the node.
    public nonisolated static let collapse = 0.06
    /// How long after the next row starts to open, its node turning green, that the pulse's dot
    /// goes, under the green node by then.
    public static let dotHold = 0.06

    /// The detail line, back on the row closing, fading in once the progress line has gone and
    /// the row is well on its way to a resting row.
    public static var detailIn: Animation {
        .easeOut(duration: 0.15).delay(0.15)
    }

    /// The detail line on the next row going as its name starts to grow.
    public static let detailOut = Animation.easeIn(duration: 0.06)

    // MARK: Open

    /// How long before the close ends that the next row starts to open, its node turning green
    /// under the pulse's dot.
    public static let growLead = 0.03
    /// The next row opening to its content's height.
    public static let open = 0.3

    /// The open's curve: quick to give the parts room, then easing in with no overshoot.
    public static var opening: Animation {
        .timingCurve(0.2, 0, 0, 1, duration: open)
    }

    /// Each part of the next exercise fading in as it rises into place.
    public static let arriveFade = 0.16
    /// How far each part rises as it comes in.
    public static let arriveRise: CGFloat = 8

    /// When `part` starts to come in, from the open's start: top first, each once the row has
    /// opened enough to hold it, the progress line once the detail line has gone (`detailOut`).
    public static func arriveDelay(_ part: Part) -> Double {
        switch part {
        case .progress: 0.06
        case .equipment: 0.08
        case .figures: 0.1
        case .slide: 0.13
        }
    }

    /// At a superset round's end, how long after the first member starts to open that "Round 2
    /// of 3" rolls to "Round 3 of 3", taking `roll`.
    public static let roundRoll = 0.12

    // MARK: After the last set

    /// After the last planned set, the Finish row fading in, from the close's start: once the
    /// last row is mostly closed, so it never shows over the slide going.
    public static let finishIn = Animation.easeOut(duration: 0.2).delay(0.22)
    /// After the last planned set, the list settling on its end, the Finish row in view.
    public static let settle = 0.35

    // MARK: The timeline

    /// When the next row starts to open, from the slide's log.
    public static var openStart: Double {
        closeStart + close - growLead
    }

    /// The whole move, from the slide's log to the next exercise's last part in place.
    public static var move: Double {
        openStart + arriveDelay(.slide) + arriveFade
    }

    /// The current exercise's parts under its name, which leave and arrive in turn.
    public enum Part {
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

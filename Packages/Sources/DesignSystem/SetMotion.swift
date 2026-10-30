import SwiftUI

/// Every timing in logging a set and moving on, in one place, so a tweak tried on the phone is one
/// line and a rebuild.
///
/// Moving to another exercise is one motion from the slide's log, about 1.25 s:
/// - **Pulse**: the node left is pulled out into a blob of green (`PulseShape`): its bottom edge
///   stretches into a neck that thins and snaps, leaving the node behind in its own color, and
///   the mass runs along the rail, drawn out the faster it goes, to the next node, which it joins
///   (`travelStart`, `travel(_:)`). There it plops in, squashing and wiggling back to a circle
///   (`plop`), with a light haptic, and the node lights as it plops (`landing(_:)`).
/// - **Hold**: nothing else moves until the landing has been seen: the pulse travels and plops on
///   a still screen, the current exercise's parts all still showing, for `landingHold` after it
///   lands, about when its wiggle has mostly settled.
/// - **Leave**: what the current exercise grew to show goes, bottom first, each part fading as it
///   drops a few points: the slide, the numbers, then the equipment and the progress line, as the
///   shift starts.
/// - **Shift** (to `shiftEnd(_:)`): the row shrinks back to a resting row as the next row grows
///   into the current exercise and the list scrolls it under the bar, down the rail (`Way.down`)
///   and back up a superset's loop (`Way.loop`) alike. Down the rail, what lies between and below
///   moves up once, never back down.
/// - **Arrive**: the next row's parts come in top first as it has room for them, each fading as
///   it rises a few points: the progress line, the equipment, the numbers, the slide.
public enum SetMotion {
    /// Which way a move goes along the rail, which sets how the shift follows the pulse.
    public enum Way: Sendable {
        /// Down to a later row: the pulse lands, then the shift runs.
        case down
        /// Back up a superset's loop to its first member: the shift follows the pulse.
        case loop
    }

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

    /// When `part` starts to go, from the slide's log: on a move to another exercise `way`, as
    /// the shift starts; with no pulse to wait for, after the last set, at once.
    static func leaveDelay(_ part: Part, way: Way? = nil) -> Double {
        let start = way.map(moveShiftStart) ?? 0
        return switch part {
        case .slide: start
        case .figures: start + leaveStagger
        case .equipment, .progress: start + leaveStagger * 2
        }
    }

    // MARK: Shift

    /// After the last set, when the row starts to close, from the slide's log: as the slide goes,
    /// so nothing waits; the row's bottom cuts off whatever is still going as it closes.
    public static let shiftStart = 0.04
    /// After the last set, the row closing as the list settles on its end, on one curve.
    public nonisolated static let shift = 0.65

    /// After the last set, the closing's curve: under way gently, as the parts go, and easing to
    /// a stop with no overshoot. With no pulse to follow, it runs on its own clock.
    public static var shifting: Animation {
        .timingCurve(0.42, 0, 0.2, 1, duration: shift).delay(shiftStart)
    }

    /// Moving to another exercise, the shift's curve, shared by both rows' heights, the names'
    /// sizes, and the list's scroll: held until the pulse has landed and plopped
    /// (`moveShiftStart(_:)`), then started from rest, easing to a stop with no overshoot.
    public static func moving(_ way: Way) -> Animation {
        .timingCurve(0.6, 0, 0.1, 1, duration: moveShift).delay(moveShiftStart(way))
    }

    /// Moving to another exercise, the shift's length.
    nonisolated static let moveShift = 0.45
    /// How long after the pulse lands the shift starts: the plop plays on a still screen, and the
    /// shift starts about when its wiggle has mostly settled. Longer, the landing holds longer.
    nonisolated static let landingHold = 0.3
    /// Moving to another exercise, when the shift starts, from the slide's log.
    public nonisolated static func moveShiftStart(_ way: Way) -> Double {
        landing(way) + landingHold
    }

    /// When the shift comes to rest, from the slide's log.
    public nonisolated static func shiftEnd(_ way: Way) -> Double {
        moveShiftStart(way) + moveShift
    }

    /// When the pulse sets off, from the slide's log: at once, ahead of everything it pulls.
    nonisolated static let travelStart = 0.02
    /// The pulse traveling from the node left to the next one's, from its pulling free to its
    /// joining. Down the rail, slow enough to watch it go; up a loop, ahead of the shift, which
    /// settles a beat after it lands.
    nonisolated static func travel(_ way: Way) -> Double {
        switch way {
        case .down: 0.5
        case .loop: 0.42
        }
    }

    /// Up a loop, the pulse's speed as it lands, against its average: an ease-out that shoots off
    /// and still hits the node moving, never creeping into it.
    nonisolated static let travelLanding = 0.6

    /// Down the rail, the power of the pulse's ease at each end: its top speed, against its
    /// average. 4 is the quartic ease-in-out Dave asked for after the quintic's 1.875 (2026-10-30).
    nonisolated static let travelEase = 4.0
    /// Up a loop, after the pulse reaches the node, how long its stretch takes to gather into a
    /// circle on it; down the rail it arrives a circle, its ease having slowed it to a stop.
    nonisolated static let collapse = 0.06

    /// When the pulse lands on the next row's node as a circle and plops in, with a light
    /// haptic, and the node lights under it, from the slide's log.
    public nonisolated static func landing(_ way: Way) -> Double {
        switch way {
        case .down: travelStart + travel(.down)
        case .loop: travelStart + travel(.loop) + collapse
        }
    }

    /// The plop: the landed pulse squashing and wiggling back to a circle on the node, a damped
    /// spring of about two and a half swings.
    nonisolated static let plop = 0.35
    /// How much wider than tall the plop squashes at its deepest, and how much shorter.
    nonisolated static let plopWiden = 0.25
    nonisolated static let plopFlatten = 0.2

    /// The plop's squash `time` after the landing, from 0, round, to 1 at its deepest, below 0
    /// as it swings the other way: a sine dying away, through two and a half swings in `plop`, to
    /// 3 % of its first by the end.
    nonisolated static func squash(at time: Double) -> Double {
        guard time > 0, time < plop else { return 0 }
        let swing = 2 * .pi * 2.5 / plop
        let decay = log(1 / 0.03) / plop
        let deepest = atan(swing / decay) / swing
        func raw(_ time: Double) -> Double {
            exp(-decay * time) * sin(swing * time)
        }
        return raw(time) / raw(deepest)
    }

    /// The detail line, back on the row closing, fading in once the progress line has gone and
    /// the row is well on its way to a resting row: on a move to another exercise `way`, timed
    /// from its shift's start.
    static func detailIn(way: Way?) -> Animation {
        .easeOut(duration: 0.15).delay(way.map { moveShiftStart($0) + 0.08 } ?? 0.15)
    }

    /// The detail line on the next row going as its name starts to grow.
    static func detailOut(way: Way?) -> Animation {
        .easeIn(duration: 0.06).delay(way.map(moveShiftStart) ?? 0)
    }

    // MARK: Arrive

    /// Each part of the next exercise fading in as it rises into place.
    static let arriveFade = 0.16
    /// How far each part rises as it comes in.
    static let arriveRise: CGFloat = 8

    /// When `part` starts to come in, from the slide's log: top first, each once the row has
    /// grown enough to hold it, the progress line once the detail line has gone (`detailOut`).
    /// On a move to another exercise `way`, each comes in once the current exercise's parts,
    /// going as the shift starts, have gone, timed from the shift's start.
    static func arriveDelay(_ part: Part, way: Way? = nil) -> Double {
        guard let way else {
            return switch part {
            case .progress: 0.2
            case .equipment: 0.28
            case .figures: 0.36
            case .slide: 0.46
            }
        }
        return moveShiftStart(way) + {
            switch part {
            case .progress: 0.14
            case .equipment: 0.18
            case .figures: 0.22
            case .slide: 0.28
            }
        }()
    }

    /// At a superset round's end, when the round just done, which the first member shows as it
    /// grows, rolls to its own, from the slide's log: once its progress line has come in.
    public static func roundRoll(_ way: Way) -> Double {
        arriveDelay(.progress, way: way) + arriveFade
    }

    // MARK: After the last set

    /// After the last planned set, the Finish row fading in, from the log: once the last row is
    /// mostly closed, so it never shows over the slide going.
    public static let finishIn = Animation.easeOut(duration: 0.2).delay(0.26)

    // MARK: The timeline

    /// The whole move, from the slide's log to the shift's end, the next exercise's last part in
    /// place and the pulse's plop settled into the lit node.
    public static func move(_ way: Way) -> Double {
        max(shiftEnd(way), arriveDelay(.slide, way: way) + arriveFade, PulseShape.runEnd(way))
    }

    /// The current exercise's parts under its name, which leave and arrive in turn.
    enum Part {
        case progress
        case equipment
        case figures
        case slide
    }

    /// Where along the travel, from 0 to 1, the pulse is a share `time` of the way through it.
    /// Down the rail, a power ease-in-out (`travelEase`): slow as its neck stretches and pulls
    /// free, fastest halfway, and slowing to a stop as it joins the next node. Up a loop, a quadratic ease-out,
    /// fastest as it sets off and landing at `travelLanding`.
    nonisolated static func distance(at time: Double, _ way: Way) -> Double {
        switch way {
        case .down:
            time < 0.5
                ? pow(2 * time, travelEase) / 2
                : 1 - pow(2 - 2 * time, travelEase) / 2
        case .loop: (2 - travelLanding) * time - (1 - travelLanding) * time * time
        }
    }

    /// The pulse's speed at a share `time` of its travel, against its average.
    nonisolated static func speed(at time: Double, _ way: Way) -> Double {
        switch way {
        case .down: travelEase * pow(1 - abs(2 * time - 1), travelEase - 1)
        case .loop: (2 - travelLanding) - 2 * (1 - travelLanding) * time
        }
    }
}

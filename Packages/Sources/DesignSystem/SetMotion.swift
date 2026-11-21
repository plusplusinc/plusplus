import SwiftUI

/// Every timing in logging a set and moving on, in one place, so a tweak tried on the phone is one
/// line and a rebuild.
///
/// Moving to another exercise is one motion from the log, 0.93 s down the rail and 1.1 s back up
/// a superset's loop (`move(_:)`):
/// - **Pulse**: the node left is pulled out into a blob of green (`PulseShape`): its bottom edge
///   stretches into a neck that thins and snaps, leaving the node behind in its own color, and
///   the mass runs along the rail, drawn out the faster it goes, to the next node, which it hits
///   moving and joins, gathering into a circle on it (`travelStart`, `travel(_:)`, `collapse`).
///   There it plops in, squashing and wiggling back to a circle
///   (`plop`), with a light haptic, and the node lights as it plops (`landing(_:)`).
/// - **Hold**: nothing else moves until the landing has been seen: the pulse travels and plops on
///   a still screen, the current exercise's parts all still showing, for `landingHold` after it
///   lands, as its first squash has sprung back.
/// - **Leave**: what the current exercise grew to show goes, bottom first, each part fading as it
///   drops a few points: the equipment, then the numbers and the progress line, as the shift
///   starts.
/// - **Shift** (to `shiftEnd(_:)`): the row shrinks back to a resting row as the next row grows
///   into the current exercise and the list scrolls it under the bar, down the rail (`Way.down`)
///   and back up a superset's loop (`Way.loop`) alike. Down the rail, what lies between and below
///   moves up once, never back down.
/// - **Arrive**: the next row's parts come in top first as it has room for them, each fading as
///   it rises a few points: the progress line, the numbers, the equipment.
public enum SetMotion {
    /// Which way a move goes along the rail, which sets the pulse's route and travel.
    public enum Way: Sendable {
        /// Down to a later row.
        case down
        /// Back up a superset's loop to its first member, at a round's end.
        case loop
    }

    // MARK: Within one exercise

    /// "Set 2 of 3" rolling to "Set 3 of 3", only the words that change, each up and out as the
    /// new one rolls up and in, once the held set's beat is over (`heldRoll`); the side word,
    /// "Left" to "Right", rolls with it.
    public static let roll = 0.3
    /// After a tap logs a set that stays on the exercise, how long it is held as still to do
    /// before the line rolls on: about as the +1 has risen. Taps inside it are dropped.
    public static let heldRoll = 0.5

    // MARK: Moving on to another exercise: leave

    /// Each part of the current exercise fading out as it goes.
    static let leaveFade = 0.09
    /// How far each part drops as it fades out.
    static let leaveDrop: CGFloat = 6
    /// How long after the part below it each part starts to go, bottom first.
    static let leaveStagger = 0.025

    /// When `part` starts to go, from the log, on a move to another exercise `way`: as the shift
    /// starts, bottom first.
    static func leaveDelay(_ part: Part, way: Way) -> Double {
        let start = moveShiftStart(way)
        return switch part {
        case .equipment: start
        case .figures, .progress: start + leaveStagger
        }
    }

    /// `part` going: on a move to another exercise `way`, held, then easing in as the shift
    /// starts; with none, as the row closes from the log, into a rest or after the last set,
    /// all at once, easing out, so each is mostly gone before the row's bottom reaches it: eased
    /// in, bottom first, the numbers were cut off at half strength over "Rest" for three frames.
    static func leaving(_ part: Part, way: Way?) -> Animation {
        guard let way else { return .easeOut(duration: leaveFade) }
        return .easeIn(duration: leaveFade).delay(leaveDelay(part, way: way))
    }

    // MARK: Shift

    /// After the last set, when the row starts to close, from the log: as its parts start to go,
    /// so nothing waits; the row's bottom cuts off whatever is still going as it closes.
    public static let closeStart = 0.04
    /// After the last set, the row closing as the list settles on its end, on one curve.
    public nonisolated static let close = 0.65

    /// After the last set, the closing's curve: under way gently, as the parts go, and easing to
    /// a stop with no overshoot. With no pulse to follow, it runs on its own clock.
    public static var closing: Animation {
        .timingCurve(0.42, 0, 0.2, 1, duration: close).delay(closeStart)
    }

    /// Moving to another exercise, the shift's curve, shared by both rows' heights, the names'
    /// sizes, and the list's scroll: held until the pulse has landed and plopped
    /// (`moveShiftStart(_:)`), then started from rest, easing to a stop with no overshoot.
    public static func moving(_ way: Way) -> Animation {
        shiftCurve.delay(moveShiftStart(way))
    }

    /// The shift's curve, as Dave tuned it: started from rest, then quick, easing to a stop.
    static var shiftCurve: Animation {
        .timingCurve(0.6, 0, 0.1, 1, duration: moveShift)
    }

    /// Moving to another exercise, the shift's length.
    nonisolated static let moveShift = 0.45
    /// How long after the pulse lands the shift starts: the plop plays on a still screen, and the
    /// shift starts as its first squash has sprung back, the wiggle settling as the rows move.
    /// Longer, the landing holds longer. 0.15 s, as Dave asked for a shorter pause (2026-11-01).
    nonisolated static let landingHold = 0.15
    /// Moving to another exercise, when the shift starts, from the log.
    public nonisolated static func moveShiftStart(_ way: Way) -> Double {
        landing(way) + landingHold
    }

    /// When the shift comes to rest, from the log.
    public nonisolated static func shiftEnd(_ way: Way) -> Double {
        moveShiftStart(way) + moveShift
    }

    /// When the pulse sets off, from the log: at once, ahead of everything it pulls.
    nonisolated static let travelStart = 0.02
    /// The pulse traveling from the node left to the next one's, from its pulling free to its
    /// joining. Down the rail, a short charge and a shot, as Dave found the longer run sluggish
    /// (2026-11-01); up a loop, ahead of the shift, which settles a beat after it lands.
    nonisolated static func travel(_ way: Way) -> Double {
        switch way {
        case .down: 0.25
        case .loop: 0.42
        }
    }

    /// Up a loop, the pulse's speed as it lands, against its average: an ease-out that shoots off
    /// and still hits the node moving, never creeping into it.
    nonisolated static let travelLanding = 0.6

    /// Down the rail, the power of the pulse's one ease in, from pulling free to the node: it
    /// charges up slowly as its neck stretches and snaps, then shoots down the rail, still
    /// speeding up as it hits the node, at this many times its average speed, as Dave asked:
    /// "charge and hit" (2026-11-01).
    nonisolated static let travelPower = 6.0
    /// After the pulse reaches the node, how long its stretch takes to gather into a circle on
    /// it: it hits the node moving, both down the rail and up a loop.
    nonisolated static let collapse = 0.06

    /// When the pulse lands on the next row's node as a circle and plops in, with a light
    /// haptic, and the node lights under it, from the log.
    public nonisolated static func landing(_ way: Way) -> Double {
        travelStart + travel(way) + collapse
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
    /// from its shift's start, once the progress line's fade is done. Earlier, the two lines
    /// were drawn one over the other for a few frames (2026-11-19).
    static func detailIn(way: Way?) -> Animation {
        .easeOut(duration: 0.15).delay(
            way.map { leaveDelay(.progress, way: $0) + leaveFade } ?? 0.15,
        )
    }

    /// The detail line on the next row going as its name starts to grow.
    static func detailOut(way: Way?) -> Animation {
        .easeIn(duration: 0.06).delay(way.map(moveShiftStart) ?? 0)
    }

    /// Out of a rest between exercises, the detail line on the next row, grown a step through the
    /// rest, going just as the progress line comes in, never before: gone as the rest ended, it
    /// left the row bare for a few frames.
    static var detailOutOfRest: Animation {
        .easeIn(duration: 0.06).delay(arriveDelay(.progress) - 0.06)
    }

    // MARK: Arrive

    /// Each part of the next exercise fading in as it rises into place.
    static let arriveFade = 0.16
    /// How far each part rises as it comes in.
    static let arriveRise: CGFloat = 8

    /// When `part` starts to come in, from the log: top first, each once the row has
    /// grown enough to hold it, the progress line once the detail line has gone (`detailOut`).
    /// On a move to another exercise `way`, each comes in once the current exercise's parts,
    /// going as the shift starts, have gone, timed from the shift's start.
    static func arriveDelay(_ part: Part, way: Way? = nil) -> Double {
        guard let way else {
            return switch part {
            case .progress: 0.2
            case .figures: 0.28
            case .equipment: 0.36
            }
        }
        // Once the row's opening bottom, on the shift's curve, has passed each: at 0.18 s the
        // figures faded in cut off by it (2026-11-19).
        return moveShiftStart(way) + {
            switch part {
            case .progress: 0.2
            case .figures: 0.28
            case .equipment: 0.36
            }
        }()
    }

    /// At a superset round's end, when the round just done, which the first member shows as it
    /// grows, rolls to its own, from the log: once its progress line has come in.
    public static func roundRoll(_ way: Way) -> Double {
        arriveDelay(.progress, way: way) + arriveFade
    }

    // MARK: A rest between exercises

    /// A rest's countdown figure turning to its new time after +15 s.
    public static let restGlide = 0.45

    /// Into a rest between exercises, or out of one, everything the move changes: the row left
    /// closing, the rest's room opening or closing, the next exercise growing, and any scroll,
    /// from the pulse setting off, easing to a stop just as the pulse's leading end reaches the
    /// place it heads for. The pulse runs to that place as it is on each frame, so the place has
    /// to be still by then: on a move's shift, after the landing, the dot landed on the next
    /// exercise's node, under the row left still open, and rode back up to the word as the rest
    /// opened (2026-11-19). The pulse barely moves through the first half of its travel
    /// (`travelPower`), while this curve has done most of its change, so the dot only goes on
    /// toward the place, never back.
    public static func aroundRest(_ way: Way) -> Animation {
        .timingCurve(0.42, 0, 0.2, 1, duration: travel(way)).delay(travelStart)
    }

    // MARK: A rest between sets

    /// Everything a log that rests between sets changes, from the tap, and the rest's end
    /// changes back, on one curve: the figures and the rest swapping in their slot, the set's
    /// segment turning purple, and the caption line rolling. The key at the bottom swaps for
    /// Skip rest and +15 s on the bar's own swap (`CountKeys`).
    public static var restSwap: Animation {
        .snappy(duration: roll)
    }

    // MARK: The timeline

    /// The whole move, from the log to the shift's end, the next exercise's last part in
    /// place and the pulse's plop settled into the lit node.
    public static func move(_ way: Way) -> Double {
        max(shiftEnd(way), arriveDelay(.equipment, way: way) + arriveFade, PulseShape.runEnd(way))
    }

    /// The current exercise's parts under its name, top to bottom, which leave and arrive in
    /// turn.
    enum Part {
        case progress
        case figures
        case equipment
    }

    /// Where along the travel, from 0 to 1, the pulse is a share `time` of the way through it. Down
    /// the rail, a power ease in (`travelPower`): slow as its neck stretches and pulls free, and
    /// speeding up all the way to the next node, fastest as it hits it. Up a loop, a quadratic
    /// ease-out, fastest as it sets off and landing at `travelLanding`.
    nonisolated static func distance(at time: Double, _ way: Way) -> Double {
        switch way {
        case .down: pow(time, travelPower)
        case .loop: (2 - travelLanding) * time - (1 - travelLanding) * time * time
        }
    }

    /// The pulse's speed at a share `time` of its travel, against its average.
    nonisolated static func speed(at time: Double, _ way: Way) -> Double {
        switch way {
        case .down: travelPower * pow(time, travelPower - 1)
        case .loop: (2 - travelLanding) - 2 * (1 - travelLanding) * time
        }
    }
}

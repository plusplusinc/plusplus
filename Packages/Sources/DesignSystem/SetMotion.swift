import SwiftUI

/// Every timing in logging a set and moving on, in one place, so a tweak tried on the phone is one
/// line and a rebuild.
///
/// Moving to another exercise is one motion from the slide's log, about 0.9 s:
/// - **Pulse**: the node left is pulled out into a blob of green (`PulseShape`): its bottom edge
///   stretches into a neck that thins and snaps, leaving the node behind in its own color, and
///   the mass runs along the rail, drawn out the faster it goes, to the next node, which it joins
///   (`travelStart`, `travel(_:)`). There it plops in, squashing and wiggling back to a circle
///   (`plop`), with a light haptic, and the node lights once it settles (`lit(_:)`).
/// - **Leave**: what the current exercise grew to show goes, bottom first, each part fading as it
///   drops a few points: the slide, the numbers, then the equipment and the progress line. Down
///   the rail (`Way.down`) the parts hold while the pulse travels and go as the shift starts;
///   back up a superset's loop (`Way.loop`) they go at once.
/// - **Shift** (to `shiftEnd(_:)`): the row shrinks back to a resting row as the next row grows
///   into the current exercise and the list scrolls it up under the bar, so what lies between and
///   below moves up once, never back down. Down the rail it starts just before the pulse lands
///   (`shiftLead`), so the landing and the shift are one motion; up the loop it follows the pulse
///   as if tethered (`TetheredShift`), settling just after it lands.
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

    /// When `part` starts to go, from the slide's log: at once, or, when the shift `waits` for
    /// the pulse, as down the rail, as the shift starts.
    static func leaveDelay(_ part: Part, waits: Bool = false) -> Double {
        let start = waits ? downShiftStart : 0
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
    /// sizes, and the list's scroll: down the rail, from just before the pulse lands; up a loop,
    /// following the pulse (`TetheredShift`).
    public static func moving(_ way: Way) -> Animation {
        switch way {
        case .down: .timingCurve(0.35, 0, 0.2, 1, duration: downShift).delay(downShiftStart)
        case .loop: Animation(TetheredShift())
        }
    }

    /// Down the rail, the shift: started from rest, easing to a stop with no overshoot.
    nonisolated static let downShift = 0.45
    /// Down the rail, how long before the pulse lands the shift starts, so the landing and the
    /// shift read as one motion rather than a stop and a start.
    nonisolated static let shiftLead = 0.08
    /// Down the rail, when the shift starts, from the slide's log.
    nonisolated static var downShiftStart: Double {
        landing(.down) - shiftLead
    }

    /// How stiffly the shift is tethered to the pulse, in radians a second: a critically damped
    /// spring's natural frequency. It trails the pulse by about `2 / tether` s as it travels and
    /// comes to rest a quarter-second after it lands; stiffer, the two move as one, looser, the
    /// list drags.
    nonisolated static let tether = 16.0

    /// When the shift comes to rest, from the slide's log.
    public nonisolated static func shiftEnd(_ way: Way) -> Double {
        switch way {
        case .down: downShiftStart + downShift
        case .loop: TetheredShift.duration
        }
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
    /// Up a loop, after the pulse reaches the node, how long its stretch takes to gather into a
    /// circle on it; down the rail it arrives a circle, its ease having slowed it to a stop.
    nonisolated static let collapse = 0.06

    /// When the pulse lands on the next row's node as a circle and plops in, with a light
    /// haptic, from the slide's log.
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

    /// When the next row's node lights, from the slide's log: as the plop settles into a circle
    /// the node's size, so the node takes its place without a seam.
    public nonisolated static func lit(_ way: Way) -> Double {
        landing(way) + plop
    }

    /// The detail line, back on the row closing, fading in once the progress line has gone and
    /// the row is well on its way to a resting row: `waits` for the pulse to land first, as the
    /// shift does down the rail.
    static func detailIn(waits: Bool) -> Animation {
        .easeOut(duration: 0.15).delay(waits ? downShiftStart + 0.08 : 0.15)
    }

    /// The detail line on the next row going as its name starts to grow.
    static func detailOut(waits: Bool) -> Animation {
        .easeIn(duration: 0.06).delay(waits ? downShiftStart : 0)
    }

    // MARK: Arrive

    /// Each part of the next exercise fading in as it rises into place.
    static let arriveFade = 0.16
    /// How far each part rises as it comes in.
    static let arriveRise: CGFloat = 8

    /// When `part` starts to come in, from the slide's log: top first, each once the row has
    /// grown enough to hold it, the progress line once the detail line has gone (`detailOut`).
    /// When the shift `waits` for the pulse, as down the rail, each comes in once the current
    /// exercise's parts, going as the shift starts, have gone, timed from the shift's start.
    static func arriveDelay(_ part: Part, waits: Bool = false) -> Double {
        guard waits else {
            return switch part {
            case .progress: 0.2
            case .equipment: 0.28
            case .figures: 0.36
            case .slide: 0.46
            }
        }
        return downShiftStart + {
            switch part {
            case .progress: 0.14
            case .equipment: 0.18
            case .figures: 0.22
            case .slide: 0.28
            }
        }()
    }

    // MARK: After the last set

    /// After the last planned set, the Finish row fading in, from the log: once the last row is
    /// mostly closed, so it never shows over the slide going.
    public static let finishIn = Animation.easeOut(duration: 0.2).delay(0.26)

    // MARK: The timeline

    /// The whole move, from the slide's log to the shift's end, the next exercise's last part in
    /// place and the pulse's plop settled into the lit node.
    public static func move(_ way: Way) -> Double {
        max(shiftEnd(way), arriveDelay(.slide, waits: way == .down) + arriveFade, lit(way))
    }

    /// The current exercise's parts under its name, which leave and arrive in turn.
    enum Part {
        case progress
        case equipment
        case figures
        case slide
    }

    /// Where along the travel, from 0 to 1, the pulse is a share `time` of the way through it.
    /// Down the rail, a quintic ease-in-out: slow as its neck stretches and pulls free, fastest
    /// halfway, and slowing to a stop as it joins the next node. Up a loop, a quadratic ease-out,
    /// fastest as it sets off and landing at `travelLanding`.
    nonisolated static func distance(at time: Double, _ way: Way) -> Double {
        switch way {
        case .down: time * time * time * (10 + time * (6 * time - 15))
        case .loop: (2 - travelLanding) * time - (1 - travelLanding) * time * time
        }
    }

    /// The pulse's speed at a share `time` of its travel, against its average.
    nonisolated static func speed(at time: Double, _ way: Way) -> Double {
        switch way {
        case .down: 30 * time * time * (1 - time) * (1 - time)
        case .loop: (2 - travelLanding) - 2 * (1 - travelLanding) * time
        }
    }
}

/// The shift as it follows the pulse: its progress is a critically damped spring, at rest at 0,
/// pulled toward where the pulse is along its travel (`SetMotion.distance(at:_:)`), so it starts
/// slowly as the pulse pulls away, trails it, and catches up just after it lands. Critically
/// damped, it never overshoots, so nothing it moves turns back. Worked out once, a sample a
/// millisecond, until it is within half a percent of the end, and scaled to end there exactly.
nonisolated struct TetheredShift: CustomAnimation {
    static let samples: [Double] = {
        let (step, substeps) = (0.001, 8)
        let omega = SetMotion.tether
        var (position, velocity, time) = (0.0, 0.0, 0.0)
        var samples = [0.0]
        while position < 0.995, samples.count < 2000 {
            for _ in 0 ..< substeps {
                let pull = omega * omega * (pulse(at: time) - position) - 2 * omega * velocity
                velocity += pull * step / Double(substeps)
                position += velocity * step / Double(substeps)
                time += step / Double(substeps)
            }
            samples.append(position)
        }
        let last = samples.last ?? 1
        return samples.map { $0 / last }
    }()

    /// How long it runs.
    static var duration: Double {
        Double(samples.count - 1) * 0.001
    }

    /// Where the pulse is along its travel up the loop, from 0 to 1, `time` after the log.
    static func pulse(at time: Double) -> Double {
        let share = (time - SetMotion.travelStart) / SetMotion.travel(.loop)
        return share <= 0 ? 0 : share >= 1 ? 1 : SetMotion.distance(at: share, .loop)
    }

    /// The shift's progress, from 0 to 1, `time` after the log.
    static func progress(at time: Double) -> Double {
        let index = time / 0.001
        guard index > 0 else { return 0 }
        guard index < Double(samples.count - 1) else { return 1 }
        let below = Int(index)
        let share = index - Double(below)
        return samples[below] + (samples[below + 1] - samples[below]) * share
    }

    func animate<V: VectorArithmetic>(
        value: V,
        time: TimeInterval,
        context _: inout AnimationContext<V>,
    ) -> V? {
        guard time < Self.duration else { return nil }
        return value.scaled(by: Self.progress(at: time))
    }
}

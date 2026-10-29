import SwiftUI

/// Every timing in logging a set and moving on, in one place, so a tweak tried on the phone is one
/// line and a rebuild.
///
/// Moving to another exercise is one motion from the slide's log, about 0.75 s:
/// - **Leave** (0 to 0.14 s): what the current exercise grew to show goes, bottom first, each part
///   fading as it drops a few points: the slide, the numbers, then the equipment and the progress
///   line.
/// - **Shift** (0 to `shiftEnd`): a green pulse sets off along the rail from the node left toward
///   the next one's (`travelStart`, `travel`), and the rest follows it as if tethered
///   (`TetheredShift`): the row shrinks back to a resting row as the next row grows into the
///   current exercise and the list scrolls it up under the bar, starting slowly as the pulse pulls
///   away, catching up, and settling just after the pulse lands, so what lies between and below
///   moves up once, never back down. The pulse is a dot on the node until the node lights.
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

    /// Moving to another exercise, the shift's curve, which follows the pulse (`TetheredShift`).
    /// Shared by both rows' heights, the names' sizes, and the list's scroll.
    public static var tethered: Animation {
        Animation(TetheredShift())
    }

    /// How stiffly the shift is tethered to the pulse, in radians a second: a critically damped
    /// spring's natural frequency. It trails the pulse by about `2 / tether` s as it travels and
    /// comes to rest a quarter-second after it lands; stiffer, the two move as one, looser, the
    /// list drags.
    nonisolated static let tether = 16.0

    /// When the shift comes to rest, from the slide's log.
    public nonisolated static var shiftEnd: Double {
        TetheredShift.duration
    }

    /// When the pulse sets off, from the slide's log: at once, ahead of everything it pulls.
    nonisolated static let travelStart = 0.02
    /// The pulse shooting from the node left to the next one's, ahead of the shift, which settles
    /// a beat after it lands.
    nonisolated static let travel = 0.42
    /// The pulse's speed as it lands, against its average: an ease-out that shoots off and still
    /// hits the node moving, never creeping into it.
    nonisolated static let travelLanding = 0.6
    /// After the pulse lands, how long its stretch takes to collapse into a dot on the node.
    nonisolated static let collapse = 0.06
    /// How long after the next row's node starts to light that the pulse's dot goes, under the
    /// green node by then: the node's color takes `roll` to change, and at 0.06 s the dot went
    /// over a node still mostly gray.
    nonisolated static let dotHold = 0.15

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
        case .equipment: 0.28
        case .figures: 0.36
        case .slide: 0.46
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
        max(shiftEnd, arriveDelay(.slide) + arriveFade, landing + dotHold)
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

/// The shift as it follows the pulse: its progress is a critically damped spring, at rest at 0,
/// pulled toward where the pulse is along its travel (`SetMotion.distance(at:)`), so it starts
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

    /// Where the pulse is along its travel, from 0 to 1, `time` after the log.
    static func pulse(at time: Double) -> Double {
        let share = (time - SetMotion.travelStart) / SetMotion.travel
        return share <= 0 ? 0 : share >= 1 ? 1 : SetMotion.distance(at: share)
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

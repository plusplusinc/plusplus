import SwiftUI

extension Transaction {
    /// How long a row's entry waits after the transaction that lets it onto its rail. With none,
    /// the transaction's own animation applies, as it does to a delete.
    @Entry public var railEntryDelay: TimeInterval?
}

/// A row's entry, in beats timed from when the row starts to show, `lead` after the rail lets
/// it go. The name fades in with a small drop. As it finishes, the line shoots down from the
/// node above to this row's node, accelerating from a running start, a throw rather than a pull
/// away from a stop. As it lands, the node pops in with a small, crisp overshoot and a light
/// haptic: the moment the add is committed. The new line and node hold in `railJoin` for a beat,
/// then fade to gray on an ease-in, with no long tail. The first row has no line above it, so
/// its node pops as the name finishes. With Reduce Motion, the line and node appear with the
/// name, gray and without a shot or an overshoot; the haptic stays.
enum RailEntry {
    static let name: TimeInterval = 0.12
    /// The shot starts as the name finishes, so the two read as one gesture: a shot starting
    /// at rest shows nothing for its first frames, so it starts a little before.
    static let shotStart: TimeInterval = 0.05
    /// With no line, the first row's node pops as its name finishes.
    static let firstPop: TimeInterval = 0.08
    static let shot: TimeInterval = 0.12
    /// The shot's speed at its start, against its average: small, but moving from the first
    /// frame, so it never looks stalled.
    nonisolated static let runningStart = 0.2
    static let pop: TimeInterval = 0.15
    /// How long the blue holds after the pop, so it registers, before it fades.
    static let hold: TimeInterval = 0.1
    static let settle: TimeInterval = 0.28

    /// When the node pops and the add is committed, from when the row starts to show.
    static func popStart(isFirst: Bool, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : isFirst ? firstPop : shotStart + shot
    }

    /// When the commit's haptic fires, from when the row is let go: as the node pops.
    static func commitTime(lead: TimeInterval, isFirst: Bool, reduceMotion: Bool) -> TimeInterval {
        lead + popStart(isFirst: isFirst, reduceMotion: reduceMotion)
    }

    /// How much of `railJoin` the new line and node show: all of it until a beat after the pop,
    /// then none, on an ease-in.
    @KeyframesBuilder<Double>
    static func joining(lead: TimeInterval, isFirst: Bool) -> some Keyframes<Double> {
        MoveKeyframe(1)
        LinearKeyframe(1, duration: lead + popStart(isFirst: isFirst, reduceMotion: false) + hold)
        LinearKeyframe(0, duration: settle, timingCurve: .easeIn)
    }

    static func content(after lead: TimeInterval) -> Animation {
        .easeOut(duration: name).delay(lead)
    }

    static func pop(isFirst: Bool, reduceMotion: Bool) -> (_ lead: TimeInterval) -> Animation? {
        let bounce = reduceMotion ? 0 : 0.25
        let start = popStart(isFirst: isFirst, reduceMotion: reduceMotion)
        return { .snappy(duration: pop, extraBounce: bounce).delay($0 + start) }
    }

    /// Where along the shot, from 0 to 1, it is a share `time` of the way through it.
    /// A quartic ease-in from a running start: most of the way in the last third, at full speed,
    /// about 3.4 times the average, as the line hits the node. Pure arithmetic, so the shot's
    /// animation can read it on any frame, off the main actor.
    nonisolated static func distance(at time: Double) -> Double {
        runningStart * time + (1 - runningStart) * pow(time, 4)
    }

    /// One stretch of the shot. The shot runs from the node above to this row's node, a stretch
    /// in each row: the row above's stretch takes its start, up to the share of the time `split`,
    /// and this row's stretch the faster rest, each following its own arc of `distance(at:)`.
    static func shot(
        from start: Double,
        to end: Double,
        reduceMotion: Bool,
    ) -> (_ lead: TimeInterval) -> Animation? {
        guard !reduceMotion, end > start else { return { _ in nil } }
        let arc = ShotArc(duration: shot * (end - start), start: start, end: end)
        return { Animation(arc).delay($0 + shotStart + shot * start) }
    }

    /// The share of the shot's time at which it crosses from the row above into this one: when
    /// it has run the row above's stretch below its node, against the span from node to node.
    /// A row estimates the span from its own height, as rows share a rhythm.
    static func split(height: CGFloat, node: CGFloat) -> Double {
        guard height > 0 else { return 0.5 }
        let share = Double((height - node) / height)
        // `distance(at:)` rises steadily, so halving finds where it reaches `share`.
        var (low, high) = (0.0, 1.0)
        for _ in 0 ..< 30 {
            let middle = (low + high) / 2
            if distance(at: middle) < share {
                low = middle
            } else {
                high = middle
            }
        }
        return (low + high) / 2
    }
}

extension View {
    /// Animates changes to `value` with `animation`, given the transaction's entry delay.
    func entry(
        _ animation: @escaping (TimeInterval) -> Animation?,
        value: some Equatable,
    ) -> some View {
        transaction(value: value) { transaction in
            if let lead = transaction.railEntryDelay {
                transaction.animation = animation(lead)
            }
        }
    }
}

/// A part of the rail an entry adds: when `trigger` changes, it shows in `railJoin`, the color
/// of something joining the rail, then settles to `rest` (`RailEntry.joining`). A keyframe
/// timeline, not an animation: a shape takes its color and its ends from one transaction, and
/// its ends move on the entry's quicker ones. With Reduce Motion, it is `rest` throughout.
private struct JoiningRail: ViewModifier {
    let trigger: Bool
    let rest: ColorToken
    let isFirst: Bool
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        // The tokens resolve here, on the main actor; the animator's frames only mix the two.
        let (rest, joined) = (Color.pp(rest), Color.pp(.railJoin))
        Group {
            if reduceMotion {
                content.foregroundStyle(rest)
            } else {
                content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, joining in
                    view.foregroundStyle(rest.mix(with: joined, by: joining))
                } keyframes: { _ in
                    RailEntry.joining(lead: place.entryLead, isFirst: isFirst)
                }
            }
        }
        .hotReloadable()
    }
}

/// A stretch of the shot as an animation: the part of `RailEntry.distance(at:)` from `start` to
/// `end` of the shot's time, rescaled to run from nothing to all of the stretch. A quartic has no
/// exact cubic timing curve, so it is computed frame by frame.
struct ShotArc: CustomAnimation {
    let duration: TimeInterval
    let start: Double
    let end: Double

    func animate<V: VectorArithmetic>(
        value: V,
        time: TimeInterval,
        context _: inout AnimationContext<V>,
    ) -> V? {
        guard time < duration else { return nil }
        let at = start + (end - start) * time / duration
        let from = RailEntry.distance(at: start)
        let progress = (RailEntry.distance(at: at) - from) / (RailEntry.distance(at: end) - from)
        return value.scaled(by: progress)
    }
}

/// The commit of an entry: a light impact as the node pops, the tap of a small thing snapping
/// into place, once per entry, Reduce Motion or not. It goes through `sensoryFeedback`, so silent
/// mode and the system's haptics setting apply. A step timed to the pop, on a clear view beside
/// the node, completes on it: the commit. Beside, not around: a completion waits for every
/// animation under it, and the node's pop would hold it back to the pop's end.
private struct Committing: ViewModifier {
    let isArriving: Bool
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var commits = 0
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        let (isFirst, reduceMotion, isArriving) = (place.isFirst, reduceMotion, isArriving)
        content
            .background {
                // Drawn, so that it animates, in the screen's own color at a hundredth of its
                // strength, so that it does not show.
                Color.pp(.background)
                    .opacity(isArriving ? 0 : 0.01)
                    .transaction(value: isArriving) { transaction in
                        guard !isArriving, let lead = transaction.railEntryDelay else { return }
                        let time = RailEntry.commitTime(
                            lead: lead,
                            isFirst: isFirst,
                            reduceMotion: reduceMotion,
                        )
                        transaction.animation = .linear(duration: 0.001).delay(time)
                        transaction.addAnimationCompletion { commits += 1 }
                    }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: commits)
            .hotReloadable()
    }
}

extension View {
    func joiningRail(
        when trigger: Bool,
        settlingTo rest: ColorToken,
        isFirst: Bool,
    ) -> some View {
        modifier(JoiningRail(trigger: trigger, rest: rest, isFirst: isFirst))
    }

    func committing(when isArriving: Bool) -> some View {
        modifier(Committing(isArriving: isArriving))
    }
}

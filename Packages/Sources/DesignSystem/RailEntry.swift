import SwiftUI

extension Transaction {
    /// Whether this transaction lets a rail's arriving row enter, so the entry's own timing
    /// applies. Otherwise the transaction's own animation does, as it does to a delete.
    @Entry public var isRailEntry = false
}

/// A row's entry, timed from when the row is let go onto its rail. At once, the line grows down
/// from the node above in the rail's gray, on a quartic ease-in from a running start, and the
/// row's place opens with it, so what follows moves in step. As the line reaches it, the node pops
/// in blue from the line's tip with a small, crisp overshoot, the row's content lands with it in
/// its own colors, a short drop that stops cleanly, and a light haptic fires: one landing. After a
/// brief hold, the node's blue cools to its own color on an ease-out, an afterglow mostly gone at
/// once. The first row has no line: its place opens over the same time, then it lands. With
/// Reduce Motion the place opens at once, nothing is blue, there is no shot or overshoot; the
/// haptic stays.
enum RailEntry {
    /// The content's landing: short, so it settles as the node's pop does.
    static let landing: TimeInterval = 0.08
    static let shot: TimeInterval = 0.2
    /// The shot's speed at its start, against its average: small, but moving from the first
    /// frame, so it never looks stalled.
    nonisolated static let runningStart = 0.2
    static let pop: TimeInterval = 0.15
    /// How long the blue holds after the pop, so it registers, before it fades. Brief: a dot
    /// that stays lit reads as a state, not an arrival.
    static let hold: TimeInterval = 0.1
    static let settle: TimeInterval = 0.3
    /// How long the well a node's drag drew takes to fade on the drop, before the new
    /// group's loop flashes, so the two never show at once.
    static let fieldFade: TimeInterval = 0.1

    /// When the node and the content land, from when the row is let go: as the line lands, the
    /// first row's too, or at once with Reduce Motion.
    static func popStart(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : shot
    }

    /// A change made all at once, `time` after the row is let go.
    static func step(at time: TimeInterval) -> Animation {
        .linear(duration: 0.001).delay(time)
    }

    /// The row's place opening, in step with the shot, the first row's too, which has no line:
    /// the space grows as far as the line on every frame. With Reduce Motion, it opens at once.
    static func space(reduceMotion: Bool) -> Animation? {
        shot(from: 0, to: 1, reduceMotion: reduceMotion)
    }

    /// How much of `railJoin` a group a node's drag made shows: none while the field fades, then
    /// all of it at once, through the pop and the hold, as a new node does, then none.
    @KeyframesBuilder<Double>
    static func groupFlash() -> some Keyframes<Double> {
        LinearKeyframe(0, duration: fieldFade)
        MoveKeyframe(1)
        LinearKeyframe(1, duration: pop + hold)
        LinearKeyframe(0, duration: settle, timingCurve: .easeOut)
    }

    /// How much of `railJoin` the new node shows: all of it through the landing and the hold, then
    /// none, on an ease-out.
    @KeyframesBuilder<Double>
    static func joining() -> some Keyframes<Double> {
        MoveKeyframe(1)
        LinearKeyframe(1, duration: popStart(reduceMotion: false) + pop + hold)
        LinearKeyframe(0, duration: settle, timingCurve: .easeOut)
    }

    /// The content's landing, with the node's pop: quick, then slowing, but still moving as it
    /// arrives, so it stops cleanly, with no soft tail.
    static func content(reduceMotion: Bool) -> Animation {
        let curve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.2, y: 0.5),
            endControlPoint: UnitPoint(x: 0.6, y: 0.9),
        )
        return .timingCurve(curve, duration: landing).delay(popStart(reduceMotion: reduceMotion))
    }

    static func pop(reduceMotion: Bool) -> Animation {
        let bounce = reduceMotion ? 0 : 0.25
        let start = popStart(reduceMotion: reduceMotion)
        return .snappy(duration: pop, extraBounce: bounce).delay(start)
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
    ) -> Animation? {
        guard !reduceMotion, end > start else { return nil }
        let arc = ShotArc(duration: shot * (end - start), start: start, end: end)
        return Animation(arc).delay(shot * start)
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
    /// Animates changes to `value` with `animation` in a transaction that lets a row enter.
    func entry(_ animation: Animation?, value: some Equatable) -> some View {
        transaction(value: value) { transaction in
            if transaction.isRailEntry {
                transaction.animation = animation
            }
        }
    }
}

/// A new node: when `trigger` changes, it shows in `railJoin`, the color of something joining the
/// rail, then settles to `rest` (`RailEntry.joining`). A keyframe timeline, not an animation: a
/// shape takes its color and its size from one transaction, and its size moves on the pop.
/// With Reduce Motion, it is `rest` throughout.
private struct JoiningRail: ViewModifier {
    let trigger: Bool
    let rest: ColorToken
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
                    RailEntry.joining()
                }
            }
        }
        .hotReloadable()
    }
}

/// Its one subview at the subview's own height, reporting `progress` of that height, so the space
/// it takes opens as `progress` goes from 0 to 1, pushing what follows down a frame at a time.
/// It does not clip: what the subview draws beyond the space still shows.
struct OpeningSpace: Layout {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let proposal = ProposedViewSize(width: bounds.width, height: nil)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
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

/// The commit of an entry: a light impact as the row's content lands, the tap of a small thing
/// settling into place, once per entry, Reduce Motion or not. It goes through `sensoryFeedback`,
/// so silent mode and the system's haptics setting apply. A step timed to the landing, on a view
/// beside the content, completes on it: the commit. Beside, not around: a completion waits for
/// every animation under it, and the content's own would hold it back.
private struct Committing: ViewModifier {
    let isArriving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var commits = 0
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        let (time, isArriving) = (RailEntry.popStart(reduceMotion: reduceMotion), isArriving)
        content
            .background {
                // Drawn, so that it animates, in the screen's own color at a hundredth of its
                // strength, so that it does not show.
                Color.pp(.background)
                    .opacity(isArriving ? 0 : 0.01)
                    .transaction(value: isArriving) { transaction in
                        guard !isArriving, transaction.isRailEntry else { return }
                        transaction.animation = RailEntry.step(at: time)
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
    ) -> some View {
        modifier(JoiningRail(trigger: trigger, rest: rest))
    }

    func committing(when isArriving: Bool) -> some View {
        modifier(Committing(isArriving: isArriving))
    }
}

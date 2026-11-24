import SwiftUI

/// The finish's "++": two "+"s that pop up from where they are placed each time `trigger`
/// changes, one on each of the finish's two beats, `beat` apart. Each shoots straight up from a
/// fixed place, growing about its own center from `startScale` to `grownScale`; the two places
/// are where a "++" string's glyphs sit at full growth, so the gap between them closes only as
/// they grow, and they meet as "++" `meeting` after the second pops. They rise on together,
/// holding for `together`, then fade as one, gone `duration` after the first. With Reduce
/// Motion each appears in place at full size on its beat, and they fade the same. Green, as it
/// is a count that went up. Only seen: it takes no touches, and nothing of it is in the
/// accessibility tree.
///
/// A keyframe animation rests at its initial value, the burst's start, where neither shows,
/// between plays, so neither can be left standing.
struct FinishBurst: View {
    /// A count, which plays the burst once each time it goes up: a Bool fired only on false to
    /// true, which can't count finishes in a row.
    let trigger: Int
    /// A time into the burst to draw it held at, with no animation, for snapshots.
    private let heldAt: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The width of one "+" as set, untransformed: the step between a "++" string's glyphs.
    @State private var glyph: CGFloat = 0

    /// How long a burst lasts, from the first "+" to both gone.
    nonisolated static let duration = 1.0
    /// From the first "+" to the second.
    nonisolated static let beat = 0.16
    /// From the second "+" to the two meeting as "++".
    private nonisolated static let meeting = 0.2
    /// How long the two rise together at full opacity before fading.
    private nonisolated static let together = 0.15
    /// How long each takes to fade in as it pops.
    private nonisolated static let fadeIn = 0.05
    /// How far each rises over the burst.
    private nonisolated static let rise: CGFloat = 30
    /// The scale each pops at, and the one it has grown to as they meet.
    private nonisolated static let startScale = 0.7
    private nonisolated static let grownScale = 1.25
    /// When the two meet as "++", from the first's pop.
    nonisolated static let met = beat + meeting

    private struct Plus {
        var opacity: Double
        var scale: Double
        var lift: CGFloat
    }

    init(trigger: Int) {
        self.trigger = trigger
        heldAt = nil
    }

    /// The burst drawn `time` into it, still, as a snapshot holds it.
    init(heldAt time: Double) {
        trigger = 0
        heldAt = time
    }

    var body: some View {
        let still = reduceMotion
        // At full growth each "+" is `grownScale` times its width, so their centers sit that
        // far apart, as a "++" at that size has them.
        let spacing = glyph * (Self.grownScale - 1)
        Group {
            if let heldAt {
                Self.pluses(at: heldAt, spacing: spacing, still: still)
            } else {
                // One track, the time into the burst, from which both "+"s are worked out: a
                // keyframe of no length, the first's wait, ahead of a cubic one left the first
                // undrawn until the two met. The animator's own view only carries the timeline.
                Color.clear.keyframeAnimator(initialValue: 0.0, trigger: trigger) { _, time in
                    Self.pluses(at: time, spacing: spacing, still: still)
                } keyframes: { _ in
                    LinearKeyframe(Self.duration, duration: Self.duration)
                }
            }
        }
        .background {
            Self.drawn(Plus(opacity: 0, scale: 1, lift: 0))
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { glyph = $0 }
        }
        .font(.ppFinishBurst)
        .foregroundStyle(.pp(.accent))
        .allowsHitTesting(false)
        // An empty representation, as `hiddenBehindDrawer` uses: `accessibilityHidden` kept
        // VoiceOver off it, but automation and `axe describe-ui` still read its text over the
        // key, between bursts too, at opacity 0.
        .accessibilityRepresentation { }
    }

    /// Both "+"s `time` into the burst, `spacing` apart. Nonisolated, as the animator draws off
    /// the main actor.
    private nonisolated static func pluses(at time: Double, spacing: CGFloat, still: Bool)
        -> some View
    {
        HStack(spacing: spacing) {
            Self.drawn(Self.plus(at: time, after: 0, still: still))
            Self.drawn(Self.plus(at: time, after: Self.beat, still: still))
        }
        .fixedSize()
    }

    /// One "+", scaled about its own center and lifted, its layout untouched by either.
    /// Nonisolated, as the animator draws off the main actor.
    private nonisolated static func drawn(_ plus: Plus) -> some View {
        Text(verbatim: "+")
            .fixedSize()
            .scaleEffect(plus.scale)
            .offset(y: -plus.lift)
            .opacity(plus.opacity)
    }

    /// A "+" that pops `delay` into the burst, `time` into it: unseen until then, it fades in,
    /// grows and rises to meet the other as "++", rises on with it, and fades with it.
    /// `still` (Reduce Motion) keeps it in place at full size.
    private nonisolated static func plus(at time: Double, after delay: Double, still: Bool)
        -> Plus
    {
        let local = time - delay
        guard local >= 0 else {
            return Plus(opacity: 0, scale: still ? grownScale : startScale, lift: 0)
        }
        let fadeStart = met + together
        let opacity = time < fadeStart
            ? min(local / fadeIn, 1)
            : max(1 - (time - fadeStart) / (duration - fadeStart), 0)
        guard !still else { return Plus(opacity: opacity, scale: grownScale, lift: 0) }
        // Both rise on one curve once they meet; the second catches up to it by then.
        let rising = { (at: Double) in rise * easeOut(min(at / duration, 1)) }
        let growth = easeOut(min(local / (met - delay), 1))
        let lift = time >= met || delay == 0
            ? rising(time)
            : rising(met) * growth
        return Plus(
            opacity: opacity,
            scale: startScale + (grownScale - startScale) * growth,
            lift: lift,
        )
    }

    /// An ease out, cubic, over `x` from 0 to 1.
    private nonisolated static func easeOut(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }
}

/// The finish's beats, for the screen that plays it.
extension PrimaryKeyButtonStyle {
    /// How long the "++" over the key lasts as a workout finishes: the screen holds under it,
    /// and the way to Log starts once it and `finishRest` are over.
    public static let finishBurst = FinishBurst.duration
    /// The beat of stillness once the burst has gone, before the drawer opens: without it the
    /// finish read as too fast (Dave, 2026-11-23).
    public static let finishRest = 0.3
    /// From the burst's first "+", and its haptic, to the second.
    public static let finishBeat = FinishBurst.beat
}

#Preview {
    @Previewable @State var finishes = 0
    Button("Finish workout") { finishes += 1 }
        .buttonStyle(.primaryKey)
        .overlay(alignment: .top) { FinishBurst(trigger: finishes).offset(y: -24) }
        .padding()
        .background(Color.pp(.background))
}

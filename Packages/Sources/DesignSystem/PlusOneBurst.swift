import SwiftUI

/// Two "+"s that pop up from where they are placed each time `trigger` changes, one on each of
/// the finish's two beats, `beat` apart. Each shoots straight up from a fixed place, growing
/// about its own center from `startScale` to `grownScale`; the two places are where a "++"
/// string's glyphs sit at full growth, so the gap between them closes only as they grow, and
/// they meet as "++" `meeting` after the second pops. They rise on together, holding for
/// `together`, then fade as one, gone `duration` after the first. With Reduce Motion each
/// appears in place at full size on its beat, and they fade the same. Green, as it is a count
/// that went up. Only seen: it takes no touches, and nothing of it is in the accessibility tree.
///
/// A keyframe animation rests at its initial value, the burst's start, where neither shows,
/// between plays, so neither can be left standing.
struct PlusOneBurst: View {
    /// A count, which plays the burst once each time it goes up: a Bool fired only on false to
    /// true, which can't count logs in a row.
    let trigger: Int

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

    private struct Plus {
        var opacity: Double
        var scale: Double
        var lift: CGFloat
    }

    var body: some View {
        let still = reduceMotion
        // At full growth each "+" is `grownScale` times its width, so their centers sit that
        // far apart, as a "++" at that size has them.
        let spacing = glyph * (Self.grownScale - 1)
        // One track, the time into the burst, from which both "+"s are worked out: a keyframe
        // of no length, the first's wait, ahead of a cubic one left the first undrawn until the
        // two met. The animator's own view only carries the timeline.
        Color.clear.keyframeAnimator(initialValue: 0.0, trigger: trigger) { _, time in
            HStack(spacing: spacing) {
                Self.drawn(Self.plus(at: time, after: 0, still: still))
                Self.drawn(Self.plus(at: time, after: Self.beat, still: still))
            }
            .fixedSize()
        } keyframes: { _ in
            LinearKeyframe(Self.duration, duration: Self.duration)
        }
        .background {
            Self.drawn(Plus(opacity: 0, scale: 1, lift: 0))
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { glyph = $0 }
        }
        .font(.ppPlusOne)
        .foregroundStyle(.pp(.accent))
        .allowsHitTesting(false)
        // An empty representation, as `hiddenBehindDrawer` uses: `accessibilityHidden` kept
        // VoiceOver off it, but automation and `axe describe-ui` still read a "+1" over the
        // key, between bursts too, at opacity 0.
        .accessibilityRepresentation { }
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
        let meet = beat + meeting
        let fadeStart = meet + together
        let opacity = time < fadeStart
            ? min(local / fadeIn, 1)
            : max(1 - (time - fadeStart) / (duration - fadeStart), 0)
        guard !still else { return Plus(opacity: opacity, scale: grownScale, lift: 0) }
        // Both rise on one curve once they meet; the second catches up to it by then.
        let rising = { (at: Double) in rise * easeOut(min(at / duration, 1)) }
        let growth = easeOut(min(local / (meet - delay), 1))
        let lift = time >= meet || delay == 0
            ? rising(time)
            : rising(meet) * growth
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

/// The +1 over the key's top, at the place the key had when the burst began, for the burst's
/// length: the key may slide away, swap for another, or leave the bar, and the +1 plays on where
/// it started. `key` is the key's bounds in this view's space, nil with no key.
struct PlusOneSpot: View {
    let trigger: Int
    let key: CGRect?

    /// What was last drawn, kept as the body draws, not in a reaction to it: the update that
    /// logs a set has to draw the +1 at the place from before it, and an `onChange` over bounds
    /// that change every frame of the key's move is skipped when two changes share a frame.
    /// A reference, so recording a draw asks for no other.
    @State private var record = Record()

    private final class Record {
        var hold = PlusOneHold()
    }

    var body: some View {
        let spot = record.hold.spot(trigger: trigger, key: key)
        let rect = spot ?? .zero
        PlusOneBurst(trigger: trigger)
            .frame(width: rect.width, height: max(rect.minY, 0), alignment: .bottom)
            .offset(x: rect.minX)
            .opacity(spot == nil ? 0 : 1)
            // A burst that follows another starts the wait again. The +1 is unseen by the end,
            // so nothing has to be drawn as it is let go.
            .task(id: trigger) {
                do {
                    try await Task.sleep(for: .seconds(PlusOneBurst.duration), tolerance: .zero)
                    record.hold.release()
                } catch { }
            }
    }
}

/// Where a +1 plays: the key's bounds from before its burst began, held until the burst is over.
struct PlusOneHold {
    /// The count and the key's bounds as last drawn.
    private var last: (trigger: Int, key: CGRect?)?
    /// The key's bounds as the burst playing began, nil between bursts.
    private var held: CGRect?
    /// A burst that began with no key plays unseen, rather than part-way over a key that comes
    /// in before its end.
    private var isUnseen = false

    /// Where the +1 is drawn with the count at `trigger` and the key at `key`, nil for nowhere.
    /// The count going up holds the key's place: the bounds drawn before, since this update may
    /// already have the key on its way out, and through a burst that follows another, the place
    /// already held.
    mutating func spot(trigger: Int, key: CGRect?) -> CGRect? {
        if let last, last.trigger != trigger, held == nil {
            held = last.key ?? key
            isUnseen = held == nil
        }
        last = (trigger, key)
        return isUnseen ? nil : held ?? key
    }

    /// The burst over, the +1 goes back to the key, unseen.
    mutating func release() {
        held = nil
        isUnseen = false
    }
}

#Preview {
    @Previewable @State var logs = 0
    Button("Log set") { logs += 1 }
        .buttonStyle(.primaryKey)
        .overlay(alignment: .top) { PlusOneBurst(trigger: logs).offset(y: -24) }
        .padding()
        .background(Color.pp(.background))
}

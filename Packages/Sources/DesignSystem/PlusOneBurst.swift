import SwiftUI

/// A "+1" that pops up from where it is placed each time `trigger` changes: it rises
/// 30 pt, growing from 0.7 to 1.25 as it fades, over 0.7 s. With Reduce Motion it flashes in
/// place, neither rising nor growing. Green, as it is a count that went up. Only seen: it takes
/// no touches, and nothing of it is in the accessibility tree.
///
/// A keyframe animation rests at its initial value, opacity 0, between plays, so the +1 can't be
/// left standing.
struct PlusOneBurst: View {
    /// A count, which plays the burst once each time it goes up: a Bool fired only on false to
    /// true, which can't count logs in a row.
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a burst lasts.
    static let duration = 0.7
    private static let rise: CGFloat = 30

    private struct Frame {
        var opacity = 0.0
        var scale = 0.7
        var lift: CGFloat = 0
    }

    var body: some View {
        Text(verbatim: "++")
            .font(.ppPlusOne)
            .foregroundStyle(.pp(.accent))
            .fixedSize()
            .keyframeAnimator(
                initialValue: Frame(scale: reduceMotion ? 1 : 0.7),
                trigger: trigger,
            ) { text, frame in
                text
                    .scaleEffect(frame.scale)
                    .offset(y: -frame.lift)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(0, duration: Self.duration - 0.05)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(reduceMotion ? 1 : 1.25, duration: Self.duration)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(reduceMotion ? 0 : Self.rise, duration: Self.duration)
                }
            }
            .allowsHitTesting(false)
            // An empty representation, as `hiddenBehindDrawer` uses: `accessibilityHidden` kept
            // VoiceOver off it, but automation and `axe describe-ui` still read a "+1" over the
            // key, between bursts too, at opacity 0.
            .accessibilityRepresentation { }
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

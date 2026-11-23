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
        Text(verbatim: "+1")
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

    @State private var hold = PlusOneHold()

    var body: some View {
        let spot = hold.spot(for: key)
        let rect = spot ?? .zero
        PlusOneBurst(trigger: trigger)
            .frame(width: rect.width, height: max(rect.minY, 0), alignment: .bottom)
            .offset(x: rect.minX)
            .opacity(spot == nil ? 0 : 1)
            .onChange(of: PlusOneHold.Input(trigger: trigger, key: key)) { old, new in
                // Every frame of a key's move comes through here; only a burst writes.
                if old.trigger != new.trigger {
                    hold.follow(from: old, to: new)
                }
            }
            // A burst that follows another starts the wait again.
            .task(id: trigger) {
                do {
                    try await Task.sleep(for: .seconds(PlusOneBurst.duration))
                    hold.release()
                } catch { }
            }
    }
}

/// Where a +1 plays: the key's bounds as its burst began, held until the burst is over.
struct PlusOneHold {
    /// What the spot is worked out from: the count of bursts and the key's bounds, nil with no
    /// key.
    struct Input: Equatable {
        let trigger: Int
        let key: CGRect?
    }

    /// The key's bounds as the burst playing began, nil between bursts.
    private(set) var held: CGRect?

    /// Where the +1 is drawn while the key is at `key`.
    func spot(for key: CGRect?) -> CGRect? {
        held ?? key
    }

    /// Holds the key's place when the count goes up: the bounds from before that update, which
    /// may already have the key on its way out, and through a burst that follows another, the
    /// place already held.
    mutating func follow(from old: Input, to new: Input) {
        if new.trigger != old.trigger {
            held = held ?? old.key ?? new.key
        }
    }

    /// The burst over, the +1 goes back to the key, unseen.
    mutating func release() {
        held = nil
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

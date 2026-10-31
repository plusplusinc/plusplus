import SwiftUI

/// A "+1" that pops up from where it is placed each time `trigger` changes: it rises
/// 30 pt, growing from 0.7 to 1.25 as it fades, over 0.7 s. With Reduce Motion it flashes in
/// place, neither rising nor growing. Green, as it is a count that went up. Only seen: it takes
/// no touches and VoiceOver passes over it.
///
/// A keyframe animation rests at its initial value, opacity 0, between plays, so the +1 can't be
/// left standing.
struct PlusOneBurst: View {
    /// A count, which plays the burst once each time it goes up: a Bool fired only on false to
    /// true, which can't count logs in a row.
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

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
            .accessibilityHidden(true)
            .hotReloadable()
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

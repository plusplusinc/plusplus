import SwiftUI

/// Slide to log a set: a light key in a track as wide as the exercise, with a quiet label naming
/// the step, "Log set", "Log left", or "Log last set". Nothing fills the track behind the key. At
/// rest the key shows an arrow; past two-thirds of the way it turns to a check and a haptic plays,
/// lighter for one side than for a whole set; slid back under, the arrow comes back. Let go past
/// that point and the set logs (`onLog`), the key finishing its slide, resting there a moment,
/// then fading out at the end and back in at the start. The key has mass: let go short of it, it
/// coasts on with the finger's speed, and where that would carry it past the point
/// (`SlideTrack.coast`), as a quick flick does, it coasts on past, the haptic plays and the set
/// logs as it crosses, and it finishes its slide; otherwise it slows and springs back, carrying
/// that speed.
///
/// The drag is horizontal only: a mostly vertical move that starts on the track scrolls the list
/// (`SlideToLogGesture`). VoiceOver reads it as one button named by its label.
public struct SlideToLog: View {
    /// What a slide logs, which sets its haptic's weight.
    public enum Weight {
        /// A whole set.
        case set
        /// One side of a set done one side at a time: a lighter haptic.
        case side
    }

    private let label: String
    private let weight: Weight
    private let onLog: () -> Void

    /// How far along the track the key is, 0 at the start, 1 at the end.
    @State private var progress: CGFloat
    /// Whether the key is going through its finish after a log, when it takes no drag.
    @State private var isFinishing: Bool
    @State private var keyOpacity: CGFloat = 1
    /// Counts the crossings of `commit` on the way out, each a haptic.
    @State private var arms = 0
    @State private var trackWidth: CGFloat = 0

    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = 56
    /// Scaled as a large title is, about half as much as the body at the accessibility sizes:
    /// scaled with the body, the key covered most of the track there and left "Log set" no room.
    /// Not held to the track's measured width: the track's width follows the key's where a
    /// layout asks for its ideal size, and the two fed each other, a layout loop at AX5.
    @ScaledMetric(relativeTo: .largeTitle) private var keyWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var arrowSize: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    public init(_ label: String, weight: Weight = .set, onLog: @escaping () -> Void) {
        self.init(label, weight: weight, progress: 0, isFinishing: false, onLog: onLog)
    }

    /// The track at a moment, so a preview or a snapshot can draw it.
    init(
        _ label: String = "Log set",
        weight: Weight = .set,
        progress: CGFloat,
        isFinishing: Bool = false,
        onLog: @escaping () -> Void = { },
    ) {
        self.label = label
        self.weight = weight
        self.onLog = onLog
        _progress = State(initialValue: progress)
        _isFinishing = State(initialValue: isFinishing)
    }

    private static let inset: CGFloat = 4

    public var body: some View {
        let keyHeight = trackHeight - Self.inset * 2
        let travel = SlideTrack.travel(track: trackWidth, key: keyWidth, inset: Self.inset)
        let keyX = Self.inset + travel * progress
        let isArmed = SlideTrack.isArmed(progress)
        ZStack(alignment: .leading) {
            // Sunk into the exercise, darker than the screen around it.
            // Concentric with the key's corners, an inset in from them.
            RoundedRectangle(cornerRadius: Self.inset + Radius.key)
                .fill(.pp(.well))
                .strokeBorder(.pp(.borderStrong), lineWidth: 1)
            Text(label)
                .font(.ppButton.weight(.regular))
                .foregroundStyle(.pp(.textSecondary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.leading, keyWidth + Self.inset * 2)
                .padding(.trailing, Self.inset * 2)
                .opacity(SlideTrack.labelOpacity(keyEnd: keyX + keyWidth, track: trackWidth))
            RoundedRectangle(cornerRadius: Radius.key)
                .fill(.pp(.textPrimary))
                .shadow(color: .pp(.shadow), radius: 1.5, y: 1)
                .overlay {
                    // Both drawn, one shown, swapped at once: animated, the one going out was left
                    // behind in the trail as the key moved on.
                    ZStack {
                        Image(systemName: "arrow.right").opacity(isArmed ? 0 : 1)
                        Image(systemName: "checkmark").opacity(isArmed ? 1 : 0)
                    }
                    .font(.system(size: arrowSize, weight: .bold))
                    .foregroundStyle(.pp(.background))
                }
                .frame(width: keyWidth, height: keyHeight)
                .offset(x: keyX)
                .opacity(keyOpacity)
        }
        .frame(height: trackHeight)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { trackWidth = $0 }
        .contentShape(.rect)
        #if os(iOS)
        .gesture(SlideToLogGesture(isEnabled: !isFinishing) { phase, translation, velocity in
            drag(phase, translation: translation, velocity: velocity, travel: travel)
        })
        #endif
        // A tap on the track does nothing, rather than open the row's sheet under it.
        .onTapGesture { }
        .sensoryFeedback(
            .impact(weight: weight == .side ? .light : .medium),
            trigger: arms,
        )
        .accessibilityRepresentation {
            Button(label, action: onLog)
        }
        .accessibilityIdentifier("workout.logSet")
        .hotReloadable()
    }

    #if os(iOS)
    private func drag(
        _ phase: SlideToLogGesture.Phase,
        translation: CGFloat,
        velocity: CGFloat,
        travel: CGFloat,
    ) {
        // The finger's speed in tracks a second.
        let speed = travel > 0 ? velocity / travel : 0
        switch phase {
        case .changed:
            let next = SlideTrack.progress(translation: translation, travel: travel)
            if SlideTrack.isArmed(next), !SlideTrack.isArmed(progress) {
                arms += 1
            }
            progress = next
        case .ended where SlideTrack.isArmed(progress):
            log(speed: speed)
        case .ended where SlideTrack.isArmed(SlideTrack.coast(from: progress, speed: speed)):
            coast(speed: speed)
        case .ended, .cancelled:
            // Slowing, then back, from the speed it was let go at, as a share of the way back.
            let share = progress > 0 ? -speed / progress : 0
            withAnimation(.interpolatingSpring(
                duration: SetMotion.springBack,
                bounce: 0,
                initialVelocity: share,
            )) {
                progress = 0
            }
        }
    }
    #endif

    /// Let go short of the commit at `speed`, with enough to carry it past: the key coasts on to
    /// the end, slowing from that speed, and the set logs, with the haptic, as it crosses.
    private func coast(speed: CGFloat) {
        isFinishing = true
        let (duration, crossing) = SlideTrack.glide(from: progress, speed: speed)
        withAnimation(.linear(duration: duration)) {
            progress = 1
        } completion: {
            rest()
        }
        // The log as the key crosses, timed from the curve by design: nothing is waited for.
        Task {
            try? await Task.sleep(for: .seconds(crossing), tolerance: .zero)
            arms += 1
            onLog()
        }
    }

    /// The key finishes its slide as the set logs, rests while the progress line rolls, then
    /// fades out at the end and in again at the start.
    private func log(speed: CGFloat = 0) {
        isFinishing = true
        onLog()
        let glide = SlideTrack.glide(from: progress, speed: speed)
        withAnimation(.linear(duration: glide.duration)) {
            progress = 1
        } completion: {
            rest()
        }
    }

    /// The key at the end, resting there, then fading out and in again at the start.
    private func rest() {
        withAnimation(.linear(duration: SetMotion.fadeOut).delay(SetMotion.rest)) {
            keyOpacity = 0
        } completion: {
            progress = 0
            withAnimation(.easeOut(duration: SetMotion.fadeIn)) {
                keyOpacity = 1
            } completion: {
                isFinishing = false
            }
        }
    }
}

/// The track's arithmetic: how far the key has gone, where it logs, and how the label fades.
enum SlideTrack {
    /// How far the key can go: the track's width less the key and an inset at each end.
    static func travel(track: CGFloat, key: CGFloat, inset: CGFloat) -> CGFloat {
        max(track - key - inset * 2, 0)
    }

    /// How far along a drag of `translation` takes the key, held within the track.
    static func progress(translation: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(translation / travel, 0), 1)
    }

    /// Whether a release at `progress` logs the set.
    static func isArmed(_ progress: CGFloat) -> Bool {
        progress >= SetMotion.commit
    }

    /// Where a key let go at `progress`, moving at `speed` tracks a second, would coast to as it
    /// slows to a stop: UIKit's projection for a scroll view's deceleration, `speed` times the
    /// rate over one less the rate, a thousandth for each millisecond.
    static func coast(from progress: CGFloat, speed: CGFloat) -> CGFloat {
        let rate = SetMotion.coastRate
        return progress + speed * rate / (1 - rate) / 1000
    }

    /// For a key coasting from `progress` at `speed` to the end, on a curve that sets off at
    /// about that speed and slows to a stop (`timingCurve(0.5, 1, 0.5, 1)`, about twice as fast
    /// at the start as on average): how long it takes, and when it crosses the commit.
    /// Let go at `speed` (tracks a second), the key keeps that speed to the end, as a thing in
    /// motion does (Dave, 2026-10-30), never slower than `glideFloor` (about 70 pt/s, only so a key let go standing still finishes), and when it crosses the
    /// commit, if it hasn't yet.
    static func glide(
        from progress: CGFloat,
        speed: CGFloat,
    ) -> (duration: Double, crossing: Double) {
        let pace = max(speed, glideFloor)
        return (
            Double(max(1 - progress, 0) / pace),
            Double(max(SetMotion.commit - progress, 0) / pace),
        )
    }

    /// The slowest a key let go past the commit finishes, in tracks a second.
    static let glideFloor: CGFloat = 0.3

    /// "Log set" fades as the key's leading edge comes over it, gone 40 pt before the end.
    static func labelOpacity(keyEnd: CGFloat, track: CGFloat) -> CGFloat {
        let fadeFrom = track * 0.45
        return min(max(1 - (keyEnd - fadeFrom) / 60, 0), 1)
    }
}

#if os(iOS)
import UIKit

/// The slide's drag, as a UIKit pan that begins only on a mostly horizontal move, so a vertical
/// swipe that starts on the track goes to the scroll view. SwiftUI's drag, set to begin on any
/// move, took the scroll view's swipes. A long press on the track, the rail's hold that lifts a
/// row, waits for it to fail: a finger resting on the key before it slides lifted the row.
struct SlideToLogGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case changed
        case ended
        case cancelled
    }

    var isEnabled: Bool
    /// Each step of the drag, with how far it has gone across and how fast it is going, in
    /// points a second.
    var onPhase: (Phase, CGFloat, CGFloat) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        let across = recognizer.translation(in: recognizer.view).x
        let speed = recognizer.velocity(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: onPhase(.changed, across, speed)
        case .ended: onPhase(.ended, across, speed)
        case .cancelled, .failed: onPhase(.cancelled, across, speed)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer,
        ) -> Bool {
            other is UILongPressGestureRecognizer
        }
    }
}
#endif

#Preview {
    VStack(spacing: Spacing.md) {
        SlideToLog("Log set") { }
        SlideToLog("Log left", weight: .side, progress: 0.4)
        SlideToLog(progress: 0.8)
        SlideToLog("Log last set", progress: 1, isFinishing: true)
    }
    .padding()
    .background(Color.pp(.background))
}

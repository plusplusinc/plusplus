import SwiftUI

/// Slide to log a set: a light key in a track as wide as the exercise, with a quiet "Log set".
/// At rest the key shows an arrow; past two-thirds of the way it turns to a check with a
/// haptic, and back if slid back under. Let go past that point and the set logs (`onLog`), the
/// key finishing its slide, resting there a moment, then fading out at the end and back in at
/// the start. Let go short of it and the key springs back.
///
/// The drag is horizontal only: a mostly vertical move that starts on the track scrolls the list
/// (`SlideToLogGesture`). VoiceOver reads it as one button, "Log set".
public struct SlideToLog: View {
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
    @ScaledMetric(relativeTo: .body) private var keyWidth: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    public init(onLog: @escaping () -> Void) {
        self.init(progress: 0, isFinishing: false, onLog: onLog)
    }

    /// The track at a moment, so a preview or a snapshot can draw it.
    init(progress: CGFloat, isFinishing: Bool = false, onLog: @escaping () -> Void = {}) {
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
            RoundedRectangle(cornerRadius: 15)
                .fill(.pp(.surface))
                .strokeBorder(.pp(.borderStrong), lineWidth: 1)
            Text("Log set")
                .font(.ppButton.weight(.regular))
                .foregroundStyle(.pp(.textSecondary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.leading, keyWidth + Self.inset * 2)
                .padding(.trailing, Self.inset * 2)
                .opacity(SlideTrack.labelOpacity(keyEnd: keyX + keyWidth, track: trackWidth))
            // A light trail behind the key, from the track's start.
            RoundedRectangle(cornerRadius: Radius.key)
                .fill(.pp(.textPrimary).opacity(0.1))
                .frame(width: keyX + keyWidth - Self.inset, height: keyHeight)
                .offset(x: Self.inset)
                .opacity(keyOpacity)
            RoundedRectangle(cornerRadius: Radius.key)
                .fill(.pp(.textPrimary))
                .shadow(color: .pp(.shadow), radius: 1.5, y: 1)
                .overlay {
                    Image(systemName: isArmed ? "checkmark" : "arrow.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.pp(.background))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: keyWidth, height: keyHeight)
                .offset(x: keyX)
                .opacity(keyOpacity)
        }
        .frame(height: trackHeight)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { trackWidth = $0 }
        .contentShape(.rect)
        #if os(iOS)
            .gesture(SlideToLogGesture(isEnabled: !isFinishing) { phase, translation in
                drag(phase, translation: translation, travel: travel)
            })
        #endif
            // A tap on the track does nothing, rather than open the row's sheet under it.
            .onTapGesture {}
            .sensoryFeedback(.impact(weight: .medium), trigger: arms)
            .accessibilityRepresentation {
                Button("Log set", action: onLog)
            }
            .accessibilityIdentifier("workout.logSet")
            .hotReloadable()
    }

    private func drag(_ phase: SlideToLogGesture.Phase, translation: CGFloat, travel: CGFloat) {
        switch phase {
        case .changed:
            let next = SlideTrack.progress(translation: translation, travel: travel)
            if SlideTrack.isArmed(next), !SlideTrack.isArmed(progress) {
                arms += 1
            }
            progress = next
        case .ended where SlideTrack.isArmed(progress):
            log()
        case .ended, .cancelled:
            withAnimation(.snappy(duration: SetMotion.springBack)) { progress = 0 }
        }
    }

    /// The key finishes its slide as the set logs, rests while the progress line rolls, then
    /// fades out at the end and in again at the start.
    private func log() {
        isFinishing = true
        onLog()
        withAnimation(.easeOut(duration: SetMotion.finish)) {
            progress = 1
        } completion: {
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
/// move, took the scroll view's swipes.
struct SlideToLogGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case changed
        case ended
        case cancelled
    }

    var isEnabled: Bool
    /// Each step of the drag, with how far it has gone across.
    var onPhase: (Phase, CGFloat) -> Void

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
        switch recognizer.state {
        case .began, .changed: onPhase(.changed, across)
        case .ended: onPhase(.ended, across)
        case .cancelled, .failed: onPhase(.cancelled, across)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
#endif

#Preview {
    VStack(spacing: Spacing.md) {
        SlideToLog {}
        SlideToLog(progress: 0.4)
        SlideToLog(progress: 0.8)
        SlideToLog(progress: 1, isFinishing: true)
    }
    .padding()
    .background(Color.pp(.background))
}

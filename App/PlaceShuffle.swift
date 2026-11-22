import SwiftUI

/// Log's Go to Workouts as two cards passing: Workouts comes up in front like a sheet being
/// presented, rising from below the screen's bottom edge to rest, opaque, its top corners rounded
/// and a soft shadow above its edge so the edge reads against the same-colored screen behind.
/// Behind it Log goes down over the same motion, `logTravel` of the screen, opaque, so what is
/// left of it above the sheet is seen moving down to meet it; it goes once hidden. Nothing fades:
/// a fading screen's stack showed the system's black layer through, and the screen went darker.
///
/// With Reduce Motion nothing slides: Log fades out over Workouts, at rest behind it. Log's stack
/// has a container background of the screen's color, so its fade never shows the system's black
/// layer through and nothing gets darker.
///
/// These transitions run only inside an animated place change, and only Log's pill animates
/// one: a place changed from the drawer swaps at once, under the drawer as it closes.
enum PlaceShuffle {
    /// A presented sheet decelerating into place, stopping dead, at about the pace the system
    /// presents one: at 0.38 s on a steeper curve the rise was over in a fifth of a second and
    /// read as way too fast.
    static let duration = 0.6
    static let animation = Animation.timingCurve(0.32, 0.72, 0.2, 1, duration: duration)

    /// How far Log goes down behind the sheet, as a share of the screen's height.
    static let logTravel: CGFloat = 1 / 3
    /// How round the sheet's top corners are as it rises; at rest they are square.
    static let cornerRadius: CGFloat = 40
    static let shadowRadius: CGFloat = 16
    static let shadowOpacity = 0.5

    /// Whether Workouts draws in front of Log: as the sheet coming up, except with Reduce Motion,
    /// where Log fades out over it.
    static func workoutsInFront(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Log going, behind the sheet: part way down, opaque.
    static func leaving(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity.animation(.easeOut(duration: duration)) : AnyTransition(SinkBack())
    }

    /// Workouts arriving in front, as a sheet.
    static func arriving(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : AnyTransition(SheetRise())
    }
}

/// The full height of the screen a view sits in, safe areas included.
private nonisolated func screenHeight(_ proxy: GeometryProxy) -> CGFloat {
    proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
}

/// Workouts as a sheet coming up from below the screen: rounded top corners and a shadow above
/// its top edge while it moves. One transition, so the shadow's card travels with the screen.
///
/// The sheet is placed by layout, the full screen tall at every step, not moved by an offset.
/// UIKit works a bar's top inset out from how far its stack overlaps the status bar: offset, the
/// stack's bar sat at the sheet's edge and caught up on its inset in a jump near the end; laid
/// out, the bar rides at the sheet's top edge as a presented sheet's does and eases into its
/// inset as the edge passes under the status bar, with no jump.
private struct SheetRise: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        let radius = phase.isIdentity ? 0 : PlaceShuffle.cornerRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radius,
            topTrailingRadius: radius,
            style: .continuous,
        )
        GeometryReader { proxy in
            content
                .mask { shape }
                .background {
                    shape
                        .fill(Color.pp(.background))
                        .shadow(
                            color: .black
                                .opacity(phase.isIdentity ? 0 : PlaceShuffle.shadowOpacity),
                            radius: PlaceShuffle.shadowRadius,
                        )
                }
                .frame(height: proxy.size.height)
                .padding(.top, phase.isIdentity ? 0 : proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

/// Log going down behind the sheet.
private struct SinkBack: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.visualEffect { content, proxy in
            content.offset(y: phase.isIdentity ? 0 : screenHeight(proxy) * PlaceShuffle.logTravel)
        }
    }
}

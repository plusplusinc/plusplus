import SwiftUI

/// Log's Go to Workouts as two cards swapping: Log, in front, is put away like a dismissed sheet,
/// sliding straight down off the screen, opaque, its top corners rounded and a soft shadow above
/// its edge so the edge reads against the same-colored screen behind. Behind it Workouts sits in
/// its own place from the first frame and grows from `startScale` to full size. Nothing fades:
/// a fading screen's bar fades its layers one by one, and the screen went darker mid-fade.
///
/// With Reduce Motion nothing slides or scales: Log fades out over Workouts, at rest behind it.
/// Log's stack has a container background of the screen's color, so its fade never shows the
/// system's black layer through and nothing gets darker.
///
/// These transitions run only inside an animated place change, and only Log's pill animates
/// one: a place changed from the drawer swaps at once, under the drawer as it closes.
enum PlaceShuffle {
    /// Long enough to read as a card put away, so it runs on a timing curve and stops dead. It
    /// eases in as well: easing out alone, the sheet's first frame jumped a sixth of the way.
    static let duration = 0.35
    static let animation = Animation.timingCurve(0.4, 0, 0.2, 1, duration: duration)

    static let startScale: CGFloat = 0.94
    /// How round a moving card's corners are; at rest they are square.
    static let cornerRadius: CGFloat = 40
    static let shadowRadius: CGFloat = 16
    static let shadowOpacity = 0.5

    /// Log going, in front: down off the screen, opaque throughout.
    static func leaving(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity.animation(.easeOut(duration: duration)) : AnyTransition(SheetEdge())
    }

    /// Workouts arriving behind Log.
    static func arriving(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : AnyTransition(CardGrow())
    }
}

/// Log as a sheet going down off the screen: rounded top corners and a shadow above its top edge
/// while it moves. One transition, so the shadow's card travels with the screen: combined with a
/// `move`, the card stayed put over the whole screen and hid Workouts.
private struct SheetEdge: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        let radius = phase.isIdentity ? 0 : PlaceShuffle.cornerRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radius,
            topTrailingRadius: radius,
            style: .continuous,
        )
        content
            .mask { shape.ignoresSafeArea() }
            .background {
                shape
                    .fill(Color.pp(.background))
                    .shadow(
                        color: .black.opacity(phase.isIdentity ? 0 : PlaceShuffle.shadowOpacity),
                        radius: PlaceShuffle.shadowRadius,
                    )
                    .ignoresSafeArea()
            }
            .visualEffect { content, proxy in
                // Past the screen's bottom edge, shadow and all.
                let below = proxy.size.height + proxy.safeAreaInsets.top
                    + proxy.safeAreaInsets.bottom + PlaceShuffle.shadowRadius * 2
                return content.offset(y: phase.isIdentity ? 0 : below)
            }
    }
}

/// Workouts growing in its place, its corners rounded until it lands.
private struct CardGrow: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .mask {
                RoundedRectangle(
                    cornerRadius: phase.isIdentity ? 0 : PlaceShuffle.cornerRadius,
                    style: .continuous,
                )
                .ignoresSafeArea()
            }
            // From the top: UIKit works the bar's safe area out from where the screen sits, so a
            // scale about the center moved the screen's top edge, the bar rode at a stale inset,
            // and it jumped 12 pt as the move ended. Pinned at the top, the inset scales with it.
            .scaleEffect(phase.isIdentity ? 1 : PlaceShuffle.startScale, anchor: .top)
    }
}

import SwiftUI

/// Log's Go to Workouts as two cards swapping: Log is put away below, sliding straight down off
/// the screen like a dismissed sheet and staying opaque, while Workouts is brought forward in
/// front of it, rising from `rise` below its place and growing from `startScale` to full size.
/// Workouts fades in over the first `fadeShare` of the move, quickly enough that the two part-
/// transparent screens never let the dark behind them show through.
///
/// With Reduce Motion nothing slides or scales: Workouts fades in over Log, which stays opaque
/// underneath until the fade ends, so nothing gets darker.
///
/// These transitions run only inside an animated place change, and only Log's pill animates
/// one: a place changed from the drawer swaps at once, under the drawer as it closes.
enum PlaceShuffle {
    /// Long enough to read as a card put away, so it eases out on a timing curve and stops dead.
    static let duration = 0.35
    static let animation = Animation.timingCurve(0.3, 0.7, 0.2, 1, duration: duration)

    static let rise: CGFloat = 40
    static let startScale: CGFloat = 0.94
    static let fadeShare = 0.3

    /// Log going: down off the screen, opaque throughout.
    static func leaving(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            // Kept fully drawn until Workouts has faded in over it, then gone at once.
            return .opacity.animation(.linear(duration: 0).delay(duration))
        }
        return .move(edge: .bottom)
    }

    /// Workouts arriving, in front of Log.
    static func arriving(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: duration))
        }
        return AnyTransition(CardRise())
    }

    /// How round the arriving card's corners start, squaring off as it lands.
    static let cornerRadius: CGFloat = 40
}

/// Workouts as a card coming forward. The mask keeps the screen's background, which ignores the
/// safe area, inside the card: unmasked, it filled the whole screen from the first frame and hid
/// Log going away beneath it.
private struct CardRise: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .mask {
                RoundedRectangle(
                    cornerRadius: phase.isIdentity ? 0 : PlaceShuffle.cornerRadius,
                    style: .continuous,
                )
                .ignoresSafeArea()
            }
            .scaleEffect(phase.isIdentity ? 1 : PlaceShuffle.startScale, anchor: .bottom)
            .offset(y: phase.isIdentity ? 0 : PlaceShuffle.rise)
    }
}

import SwiftUI

/// Log's Go to Workouts as two screens trading places softly: Workouts fades in on top of Log
/// while rising `distance` to its place, and Log, opaque underneath, settles `distance` down as it
/// gives way, gone once Workouts is opaque over it. One motion, easing out to a dead stop.
///
/// Nothing gets darker: Log stays opaque under the fade, the backdrop behind both is the screen's
/// color, and each screen's stack has a container background of that color, so a fading stack
/// never shows the system's black layer through (the plain fade went darker mid-way).
///
/// Both screens move by layout, full height at every step, not by an offset: offset, a stack's
/// bar works its top inset out from where the moved screen sits and jumped when the move ended.
///
/// With Reduce Motion nothing moves: Workouts fades in over Log alone.
///
/// These transitions run only inside an animated place change, and only Log's pill animates
/// one: a place changed from the drawer swaps at once, under the drawer as it closes.
enum PlaceCrossfade {
    static let duration = 0.3
    static let animation = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: duration)

    /// How far each screen moves: Workouts up into place, Log down out of it.
    static let distance: CGFloat = 24

    /// Log going, under Workouts' fade: opaque, settling down a little.
    static func leaving(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? held : AnyTransition(Shift(distance: distance, fades: false))
    }

    /// Workouts arriving on top: fading in as it rises into place.
    static func arriving(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(Shift(distance: distance, fades: true))
    }

    /// Log kept drawn, unmoved, until Workouts has faded in over it: its own fade waits for the
    /// motion's end, where Workouts is all that shows.
    private static let held = AnyTransition.opacity
        .animation(.timingCurve(1, 0, 1, 0, duration: duration))
}

/// A screen shifted down by `distance` on the way in or out, and faded with `fades`.
private struct Shift: Transition {
    let distance: CGFloat
    let fades: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        GeometryReader { proxy in
            content
                .frame(height: proxy.size.height)
                .padding(.top, phase.isIdentity ? 0 : distance)
        }
        .ignoresSafeArea()
        .opacity(fades && !phase.isIdentity ? 0 : 1)
    }
}

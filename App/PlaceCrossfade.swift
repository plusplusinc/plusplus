import SwiftUI

/// Log's Go to Workouts as two screens trading places softly: Workouts fades in on top of Log
/// while moving `distance` sideways into its place from `arrivingFrom`, and Log, opaque
/// underneath, moves `distance` to the left as it gives way, gone once Workouts is opaque over
/// it. One motion, easing out to a dead stop.
///
/// Nothing gets darker: Log stays opaque under the fade, the backdrop behind both is the screen's
/// color, and each screen's stack has a container background of that color, so a fading stack
/// never shows the system's black layer through (the plain fade went darker mid-way). A sideways
/// offset leaves the screens' top edges where they are, so their bars keep their insets.
///
/// With Reduce Motion nothing moves: Workouts fades in over Log alone.
///
/// These transitions run only inside an animated place change, and only Log's pill animates
/// one: a place changed from the drawer swaps at once, under the drawer as it closes.
enum PlaceCrossfade {
    static let duration = 0.3
    static let animation = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: duration)

    /// How far each screen moves.
    static let distance: CGFloat = 24
    /// The side Workouts comes in from: from the leading side it travels the opposite way to Log,
    /// as the old screen going left and the new one going right.
    static let arrivingFrom = HorizontalEdge.leading

    /// Log going, under Workouts' fade: opaque, moving to the left.
    static func leaving(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? held : AnyTransition(Shift(x: -distance, fades: false))
    }

    /// Workouts arriving on top: fading in as it moves into place.
    static func arriving(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return AnyTransition(Shift(x: arrivingFrom == .leading ? -distance : distance, fades: true))
    }

    /// Log kept drawn, unmoved, until Workouts has faded in over it: its own fade waits for the
    /// motion's end, where Workouts is all that shows.
    private static let held = AnyTransition.opacity
        .animation(.timingCurve(1, 0, 1, 0, duration: duration))
}

/// A screen offset sideways by `x` on the way in or out, and faded with `fades`.
private struct Shift: Transition {
    let x: CGFloat
    let fades: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(x: phase.isIdentity ? 0 : x)
            .opacity(fades && !phase.isIdentity ? 0 : 1)
    }
}

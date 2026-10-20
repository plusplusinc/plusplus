import CoreGraphics

/// A swipe that opens or closes a `SideDrawer`: the pure arithmetic of how far open the finger
/// holds it and where it settles when let go, so it is tested without a touch.
nonisolated enum DrawerDrag {
    /// How near the screen's left edge a swipe has to start to open the drawer: inside the rail
    /// column's nodes, which start further in, so a hold on one still lifts it.
    static let edge: CGFloat = 24
    /// How fast a release has to be moving, in points a second, to settle the way it moves
    /// whatever its position: a flick.
    static let flickSpeed: CGFloat = 400
    /// How far a swipe goes before it opens or closes the drawer with Reduce Motion on, where
    /// nothing follows the finger.
    static let reducedMotionReach: CGFloat = 30

    /// How far open, 0 to 1, with the finger `translation` points right of where it started,
    /// from `start` open, over a drawer `width` wide.
    static func progress(translation: CGFloat, width: CGFloat, from start: CGFloat) -> CGFloat {
        guard width > 0 else { return start }
        return min(max(start + translation / width, 0), 1)
    }

    /// Whether the drawer settles open when let go at `progress`, the finger moving `velocity`
    /// points a second (right is positive): the way a flick goes, else whichever side of
    /// halfway it is on.
    static func settlesOpen(progress: CGFloat, velocity: CGFloat) -> Bool {
        if velocity >= flickSpeed {
            return true
        }
        if velocity <= -flickSpeed {
            return false
        }
        return progress >= 0.5
    }

    /// Whether the drawer ends up open after a swipe of `translation` points with Reduce
    /// Motion on: a swipe that goes `reducedMotionReach` the way that changes it does.
    static func swipeOpens(translation: CGFloat, fromOpen: Bool) -> Bool {
        fromOpen ? translation > -reducedMotionReach : translation >= reducedMotionReach
    }

    /// The settling spring's starting speed, in lengths of the rest of its way a second, so the
    /// drawer leaves the finger at the speed it was moving. Never backward, and capped, so a
    /// release a hair from where it settles doesn't shoot off.
    static func releaseSpeed(
        velocity: CGFloat,
        progress: CGFloat,
        opens: Bool,
        width: CGFloat,
    ) -> CGFloat {
        let remaining = (opens ? 1 - progress : progress) * width
        guard remaining > 1 else { return 0 }
        let toward = opens ? velocity : -velocity
        return min(max(toward / remaining, 0), maxReleaseSpeed)
    }

    private static let maxReleaseSpeed: CGFloat = 20
}

extension DrawerDrag {
    /// A step of a swipe, as the gesture reports it: how far right of where it started the
    /// finger is, and, let go, how fast it was moving, in points a second.
    enum Phase {
        case changed(translation: CGFloat)
        case ended(translation: CGFloat, velocity: CGFloat)
        case cancelled
    }
}

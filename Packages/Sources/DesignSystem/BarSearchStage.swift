import SwiftUI

/// Where `BarSearchField`'s opening or closing is: the two ends, and the beats between them.
nonisolated enum BarSearchStage {
    case closed
    /// Opening: the search button's glass grows to the left toward the leading button.
    case growing
    /// Opening: the field runs on over the leading button and the X parts from its end.
    case splitting
    case open
    /// Closing: the field's end runs back over the X; the leading button is back, under the
    /// field's leading end.
    case covering
    /// Closing: the field shrinks back into the search button.
    case shrinking

    /// Under the field, its label faded, until it goes once the field has covered it, and from
    /// before the field's leading end pulls back off it.
    var showsLeading: Bool {
        self != .open
    }

    /// Opening, drawn small into the field's leading end as the two fuse. Closing, it comes back
    /// whole under the field's end, its own shape, and is uncovered as the field shrinks.
    var absorbsLeading: Bool {
        self == .splitting
    }

    /// Back as the field's end leaves it, closing (`BarGlassButtonStyle` holds it back a moment).
    var showsLeadingLabel: Bool {
        self == .closed || self == .growing || self == .shrinking
    }

    var showsFieldContent: Bool {
        self == .growing || self == .splitting || self == .open
    }

    /// The X's own glass, apart from the field's: from the split until the X has run back in.
    var showsX: Bool {
        self != .closed && self != .shrinking
    }

    var showsXSymbol: Bool {
        self == .splitting || self == .open
    }

    var showsSearchSymbol: Bool {
        self == .closed || self == .shrinking
    }

    /// The search glass's leading and trailing ends in the item, which is `itemWidth` wide with
    /// the search button at its trailing edge. Growing, it stops `Self.meeting` short of the
    /// leading button: apart, but within the container's raised spacing, so the two join with a
    /// neck before the next beat fuses them.
    func span(itemWidth: CGFloat, height: CGFloat, leadingWidth: CGFloat) -> (CGFloat, CGFloat) {
        switch self {
        case .closed, .shrinking: (itemWidth - height, itemWidth)
        case .growing: (leadingWidth + Self.meeting, itemWidth)
        case .splitting, .open: (0, itemWidth - height - Spacing.sm)
        case .covering: (0, itemWidth)
        }
    }

    private static let meeting: CGFloat = 6
}

/// `BarSearchField`'s beats.
nonisolated enum BarSearchTiming {
    /// How long the field grows before it fuses with the leading button and splits the X off: as
    /// its end comes within a neck of the leading button.
    static let growing = Duration.seconds(0.24)
    /// How long the field takes to cover the leading button, which then goes.
    static let splitting = Duration.seconds(0.25)
    /// How long the X's glass takes to run back into the field's end before the field shrinks.
    static let covering = Duration.seconds(0.1)
    /// The field shrinking back into the search button. It starts slowly, so the leading button
    /// pulls off the field's end rather than snapping off it: on `tapChange`, whose spring starts
    /// fast, two glasses parted between one frame and the next.
    static let shrinking = Animation.easeInOut(duration: 0.28)
    /// When the field has shrunk back into the search button.
    static let shrunk = Duration.seconds(0.28)
    /// With Reduce Motion, the two ends crossfade in one step.
    static let crossfade = Animation.easeInOut(duration: 0.2)
}

/// The glass container's spacing over an opening or closing. Shapes closer than the spacing blend
/// with a neck between them, so it is raised while the field meets the leading button and the X
/// parts from it, and comes back down to the gap between them at rest, the neck thinning out as
/// the X settles. The container takes its spacing only as set in an update, not along an
/// animation, so a timeline sets it on every frame.
nonisolated struct GlassSpacingRamp {
    let start: Date
    /// Seconds from the start, and the spacing then; eased between them.
    let points: [(TimeInterval, CGFloat)]

    var end: Date {
        start.addingTimeInterval(points.last?.0 ?? 0)
    }

    func spacing(at date: Date) -> CGFloat {
        let time = date.timeIntervalSince(start)
        guard let first = points.first, let last = points.last else { return Spacing.sm }
        guard time > first.0 else { return first.1 }
        guard time < last.0 else { return last.1 }
        for (from, to) in zip(points, points.dropFirst()) where time < to.0 {
            let progress = (time - from.0) / (to.0 - from.0)
            let eased = progress * progress * (3 - 2 * progress)
            return from.1 + (to.1 - from.1) * eased
        }
        return last.1
    }

    /// The spacing the field and the X, and the field and the leading button, blend within.
    static let raised: CGFloat = 24

    /// Up as the field grows, held while it meets the leading button and splits the X off, and
    /// down as the X settles.
    static func opening(at start: Date) -> Self {
        Self(
            start: start,
            points: [(0, Spacing.sm), (0.08, raised), (0.38, raised), (0.66, Spacing.sm)],
        )
    }

    /// Up as the X runs back into the field, held while the leading button pulls out of it, and
    /// down as the field shrinks into the search button.
    static func closing(at start: Date) -> Self {
        Self(
            start: start,
            points: [(0, Spacing.sm), (0.08, raised), (0.28, raised), (0.46, Spacing.sm)],
        )
    }
}

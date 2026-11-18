import SwiftUI

/// Where `BarSearchField` is between closed (`progress` 0) and open (1): every shape's place and
/// every fade, worked out from the one progress, so the necks and the shapes move on one clock
/// and one curve. Closing runs the same progress back.
///
/// The item is `itemWidth` wide, the leading button at its leading edge and the search button at
/// its trailing edge. The search glass's leading end runs from the search button to the item's
/// leading edge at one speed along the curve, meeting the leading button with a neck about four
/// fifths of the way, then running on over it. From `splitStart` on, the field's trailing end
/// pulls back, and the X's glass fills where it was, out to where the search button was, then
/// parts from it with a neck that pinches off at the end.
///
/// No two glasses overlap: the leading button's glass keeps only what the field has not reached,
/// and the X's only what the field's end has left. Overlapping, the glass under the field showed
/// through it as a darker shape; touching, the two blend into one with a waist.
nonisolated struct BarSearchMotion {
    let progress: CGFloat
    let itemWidth: CGFloat
    let height: CGFloat
    let leadingWidth: CGFloat

    /// The search glass's leading end, at the item's leading edge a little before the curve's
    /// end, where its speed is already near nothing: on the curve's slow tail, the last of the
    /// leading button's glass lingered beside the field.
    var searchStart: CGFloat {
        (itemWidth - height) * (1 - min(progress / Self.leadingCovered, 1))
    }

    /// The search glass's trailing end: the item's until the split, then the X's width and the
    /// gap to it short of it.
    var searchEnd: CGFloat {
        itemWidth - (height + Spacing.sm) * ease(from: Self.splitStart, to: 1)
    }

    /// The leading button's glass, from its leading edge to the field's leading end once that has
    /// reached it; nil for all of it.
    var leadingGlassWidth: CGFloat? {
        searchStart < leadingWidth ? searchStart : nil
    }

    /// Gone once the field has run over it.
    var showsLeading: Bool {
        progress < 1 && (leadingGlassWidth ?? .infinity) > Self.sliver
    }

    /// The X's glass: from the field's trailing end, or where the search button's leading edge
    /// was once the end has passed it, to the item's trailing edge.
    var xStart: CGFloat {
        max(itemWidth - height, searchEnd)
    }

    var showsX: Bool {
        itemWidth - xStart > Self.sliver
    }

    /// Fades from the field's end touching the button to its having run over half of it.
    var leadingLabelOpacity: CGFloat {
        clamp((searchStart - leadingWidth / 2) / max(leadingWidth / 2, 1))
    }

    /// The field's own symbol, prompt, and caret: in once the field is wider than the search
    /// button, and out before it is back to it, where they ran under its symbol.
    var fieldOpacity: CGFloat {
        ease(from: Self.fieldFadeStart, to: Self.fieldFadeEnd)
    }

    var searchSymbolOpacity: CGFloat {
        1 - ease(from: 0, to: Self.searchSymbolGone)
    }

    /// The X's symbol grows in as its glass parts from the field.
    var xSymbol: CGFloat {
        ease(from: Self.xSymbolStart, to: 1)
    }

    /// The bar's own title fades as the field's end crosses it, at the screen's middle.
    var titleOpacity: CGFloat {
        1 - ease(from: Self.titleFadeStart, to: Self.titleFadeEnd)
    }

    /// The container's spacing: shapes closer than it blend with a neck between them. Up as the
    /// motion starts, so the field meets the leading button and parts from the X with a neck, and
    /// back down to the gap between the field and the X as the X settles, so the neck thins out
    /// and pinches off with the motion's end.
    var spacing: CGFloat {
        let raised = ease(from: 0, to: Self.spacingUp) * (1 - ease(from: Self.spacingDown, to: 1))
        return Spacing.sm + (Self.raisedSpacing - Spacing.sm) * raised
    }

    /// Smoothstep over a part of the progress, 0 before it and 1 after: each part starts and
    /// ends at rest, so nothing it moves jumps where the part begins or ends.
    private func ease(from start: CGFloat, to end: CGFloat) -> CGFloat {
        let part = clamp((progress - start) / (end - start))
        return part * part * (3 - 2 * part)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    /// Where the field's trailing end starts pulling back off the X: a little before the field's
    /// leading end meets the leading button, so the two happen together.
    static let splitStart: CGFloat = 0.55
    /// Where the field's leading end reaches the item's leading edge.
    static let leadingCovered: CGFloat = 0.95
    /// A glass narrower than this is not drawn.
    static let sliver: CGFloat = 0.5
    static let fieldFadeStart: CGFloat = 0.15
    static let fieldFadeEnd: CGFloat = 0.45
    static let searchSymbolGone: CGFloat = 0.3
    static let xSymbolStart: CGFloat = 0.6
    static let titleFadeStart: CGFloat = 0.15
    static let titleFadeEnd: CGFloat = 0.55
    /// The spacing the field and the leading button, and the field and the X, blend within.
    static let raisedSpacing: CGFloat = 24
    static let spacingUp: CGFloat = 0.1
    static let spacingDown: CGFloat = 0.85
}

/// `BarSearchField`'s curves.
nonisolated enum BarSearchTiming {
    /// Opening and closing alike: the whole motion on one curve that starts at once and eases
    /// out, so it stops dead at either end. A spring per beat surged and stalled two or three
    /// times in one gesture.
    static let moving = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.5)
    /// With Reduce Motion, the two ends crossfade in one step.
    static let crossfade = Animation.easeInOut(duration: 0.2)
}

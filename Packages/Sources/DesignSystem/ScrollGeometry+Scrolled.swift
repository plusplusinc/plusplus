import SwiftUI

extension ScrollGeometry {
    /// How far the content is scrolled, as `ScrollPosition.scrollTo(y:)` counts: from the
    /// content's top, not from above the top inset, where `contentOffset` counts from.
    public var scrolledY: CGFloat {
        contentOffset.y + contentInsets.top
    }

    /// The furthest `scrollTo(y:)` goes: the content's end at the bottom of the container, the
    /// area between the bars.
    public var endY: CGFloat {
        max(contentSize.height - containerSize.height, 0)
    }
}

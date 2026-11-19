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

/// The part of a vertical list's scroll geometry that a scroll to a `scrollTo(y:)` value reads:
/// how tall the content and the area between the bars are, and how far it is scrolled. What to
/// react to in place of the whole `ScrollGeometry`, whose insets and visible rect change on
/// their own: pushed under a bar and over a `safeAreaBar`, a list's geometry is laid out several
/// times in the push's first frame, the bars' room leaving the container and then the insets
/// growing to it, and a reaction to all of it ran on each, which SwiftUI logs as an
/// `OnScrollGeometryChange` fault. Only the container's change reaches these.
public struct ScrollExtent: Equatable, Sendable {
    public var contentHeight: CGFloat
    public var containerHeight: CGFloat
    /// As `ScrollGeometry.scrolledY` counts.
    public var scrolledY: CGFloat

    public init(_ geometry: ScrollGeometry) {
        contentHeight = geometry.contentSize.height
        containerHeight = geometry.containerSize.height
        scrolledY = geometry.scrolledY
    }

    /// As `ScrollGeometry.endY` counts.
    public var endY: CGFloat {
        max(contentHeight - containerHeight, 0)
    }
}

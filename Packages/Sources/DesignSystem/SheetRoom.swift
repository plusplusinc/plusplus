import SwiftUI

/// Room under a list's end while a half-height sheet covers the screen's foot, so the list can
/// scroll its last row up to just above the sheet.
public enum SheetRoom {
    /// How tall the room is: enough that, scrolled to its end, the list's last row rests `gap`
    /// above the sheet's top, and none where it already does. `listBottom` is where the list's
    /// end rests on screen when scrolled to it, and `tail` what the content already holds under
    /// the last row.
    public static func height(
        sheetTop: CGFloat,
        listBottom: CGFloat,
        tail: CGFloat,
        gap: CGFloat,
    ) -> CGFloat {
        max(0, listBottom - sheetTop - tail + gap)
    }
}

extension View {
    /// `height` of room under this view, in its content, out of sight. It animates as it
    /// changes, frame by frame in the content's size, so a scroll view can hold its end in step
    /// as it closes: as a padding, the content's size took its end value at once.
    public func roomUnderSheet(_ height: CGFloat) -> some View {
        RoomUnderSheet(height: height) { self }
    }
}

/// Its one subview, with `height` of room under it.
private struct RoomUnderSheet: Layout {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(Self.content(proposal)) ?? .zero
        return CGSize(width: size.width, height: size.height + height)
    }

    /// What the content is offered: the width, and its own height, as a scroll view offers.
    private static func content(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width, height: nil)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: Self.content(proposal),
        )
    }
}

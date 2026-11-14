import SwiftUI

extension View {
    /// While `isOn`, and while the list's rows resize (`listResizes(_:)`), room under this view
    /// as tall as the scroll view it is in shows, out of sight, so the list can scroll its end up
    /// to the top, and rows shrinking as it scrolls back to its top don't pull it up short. Sized
    /// in the same layout pass as the list, so a change to what shows, as a workout's margin
    /// coming or going, changes it at once: as a height read back from the scroll view, it
    /// changed the list a second time in the frame.
    public func roomBelow(_ isOn: Bool) -> some View {
        modifier(RoomBelow(isOn: isOn))
    }

    /// While `top` is set, room under this view, out of sight, so the list can scroll to `top`,
    /// where a row lands under the bar, even where what follows the row is shorter than the
    /// height the scroll view shows above its content margin. Worked out in the pass that lays
    /// the list out, from its own height and the scroll view's, so it is right on every frame of a
    /// growth: the scroll view's height read back into state, as `roomBelow` found, changed the
    /// list a second time in a frame. None while `top` is nil.
    public func roomToLand(top: CGFloat?) -> some View {
        RoomToLand(top: top ?? 0, isOn: top != nil) {
            self
            // What the scroll view shows above its content margin, measured in the same pass.
            Color.clear.containerRelativeFrame(.vertical)
        }
    }
}

/// Its first subview, with room under it while `isOn`: as much as `top` plus what the scroll view
/// shows, its second subview's height, reaches past its height. So while it is on, the content is
/// never too short for the scroll view to reach `top`, whatever else under it comes or goes, and
/// however short the first subview is. `top` animates, so the room can close over a motion.
private struct RoomToLand: Layout {
    var top: CGFloat
    let isOn: Bool

    var animatableData: CGFloat {
        get { top }
        set { top = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        guard isOn, subviews.count > 1 else { return size }
        let visible = subviews[1].sizeThatFits(proposal).height
        return CGSize(width: size.width, height: max(size.height, top + visible))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
        // Measured only: placed at the top with no size of its own in the room.
        subviews.dropFirst().first?.place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
    }
}

/// Its content, with room under it while `isOn` or while the list's rows resize.
private struct RoomBelow: ViewModifier {
    let isOn: Bool
    @Environment(\.isListResizing) private var isResizing

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            if isOn || isResizing {
                Color.clear.containerRelativeFrame(.vertical)
            }
        }
    }
}

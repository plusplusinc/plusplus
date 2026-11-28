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
    /// list a second time in a frame. None while `top` is nil and no mark counts.
    ///
    /// With `fromMark`, while a view inside is marked `landingMark(true)`, the room is on and its
    /// top is that view's top, read in the same pass rather than read back from where the view
    /// was laid out.
    public func roomToLand(top: CGFloat?, fromMark: Bool = false) -> some View {
        RoomToLand(top: top ?? 0, isOn: top != nil, fromMark: fromMark) {
            self
            // What the scroll view shows above its content margin, measured in the same pass.
            Color.clear.containerRelativeFrame(.vertical)
        }
    }

    /// While `isOn`, marks this view's top as where a `roomToLand(top:fromMark:)` around it
    /// lands. One view at a time is marked. Off, the top goes on a guide nothing reads, so the
    /// view stays the same view either way.
    public func landingMark(_ isOn: Bool) -> some View {
        alignmentGuide(isOn ? .landing : .unmarked) { $0[.top] }
    }
}

extension VerticalAlignment {
    /// The top of the view marked `landingMark(true)`, which the layouts above it merge up, as a
    /// layout does a guide only one of its subviews has.
    private nonisolated enum Landing: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.top]
        }
    }

    /// Where `landingMark(false)` puts it.
    private nonisolated enum Unmarked: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.top]
        }
    }

    fileprivate nonisolated static let landing = VerticalAlignment(Landing.self)
    fileprivate nonisolated static let unmarked = VerticalAlignment(Unmarked.self)
}

/// Its first subview, with room under it while `isOn`: as much as `top` plus what the scroll view
/// shows, its second subview's height, reaches past its height. So while it is on, the content is
/// never too short for the scroll view to reach `top`, whatever else under it comes or goes, and
/// however short the first subview is. `top` animates, so the room can close over a motion.
/// With `fromMark`, while the first subview has a marked view, the room is on and `top` is the
/// mark's.
private struct RoomToLand: Layout {
    var top: CGFloat
    let isOn: Bool
    let fromMark: Bool

    var animatableData: CGFloat {
        get { top }
        set { top = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let first = subviews.first else { return .zero }
        let size = first.sizeThatFits(proposal)
        let mark = fromMark ? first.dimensions(in: proposal)[explicit: .landing] : nil
        guard isOn || mark != nil, subviews.count > 1 else { return size }
        let visible = subviews[1].sizeThatFits(proposal).height
        let top = mark ?? top
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

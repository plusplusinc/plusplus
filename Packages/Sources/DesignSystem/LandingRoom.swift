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
    ///
    /// With `fromMark`, `top` is where the view marked `landingMark(true)` inside it is laid out,
    /// read in the same pass, while one is: as `top` read back from that view's place, the room
    /// came a pass after the scroll view's size, and as the app reopened into a short workout the
    /// list's height changed twice in that frame.
    public func roomToLand(top: CGFloat?, fromMark: Bool = false) -> some View {
        RoomToLand(top: top ?? 0, isOn: top != nil, fromMark: fromMark) {
            self
            // What the scroll view shows above its content margin, measured in the same pass.
            Color.clear.containerRelativeFrame(.vertical)
        }
    }

    /// While `isOn`, marks this view's top as the place a `roomToLand(top:fromMark:)` around it
    /// lands. One view at a time is marked. Applied whether on or not, so turning it off keeps
    /// the view's identity.
    public func landingMark(_ isOn: Bool) -> some View {
        LandingMark(isOn: isOn) { self }
    }
}

extension VerticalAlignment {
    /// The top of the view marked `landingMark(true)`, which containers pass up unchanged.
    private nonisolated enum Landing: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.top]
        }
    }

    fileprivate nonisolated static let landing = VerticalAlignment(Landing.self)
}

/// Its subview as it is, giving `VerticalAlignment.landing` an explicit value, its top, while
/// `isOn`. The layouts between it and `RoomToLand` merge it up, as a layout does a guide only
/// one of its subviews has.
private struct LandingMark: Layout {
    let isOn: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGFloat? {
        if guide == .landing {
            return isOn ? bounds.minY : nil
        }
        return subviews.first?.dimensions(in: proposal)[explicit: guide].map { bounds.minY + $0 }
    }
}

/// Its first subview, with room under it while `isOn`: as much as `top` plus what the scroll view
/// shows, its second subview's height, reaches past its height. So while it is on, the content is
/// never too short for the scroll view to reach `top`, whatever else under it comes or goes, and
/// however short the first subview is. `top` animates, so the room can close over a motion.
/// With `fromMark`, while the first subview has a marked view (`LandingMark`), the room is on and
/// `top` is the mark's.
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
        let top = mark.map { max($0, 0) } ?? top
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

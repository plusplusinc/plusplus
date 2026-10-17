import SwiftUI

extension View {
    /// Lets a row held on a rail inside this scroll view scroll it: dragged toward the top or
    /// bottom of the area the list shows in, into the band at that edge, the list scrolls, faster
    /// the nearer the edge, and the card
    /// stays under the finger as the rows pass under it. Let go outside that area, over a bar,
    /// the row goes back where it was.
    public func railAutoscroll(_ position: Binding<ScrollPosition>) -> some View {
        modifier(RailAutoscroll(position: position))
    }
}

/// What a held row and the scroll view around it share: where the finger is in the scroll view,
/// where the list shows in it, and how far the list has scrolled under the finger.
@Observable
final class RailEdges {
    /// Whether a row is held, which is when the list may scroll on its own.
    @ObservationIgnored var isHeld = false {
        didSet {
            scrolledTo = nil
            travel = RailDrag.Travel(from: fingerY)
            updateScrolling()
        }
    }

    /// The held finger's y in the scroll view's space.
    @ObservationIgnored var fingerY: CGFloat = 0 {
        didSet {
            travel.pass(fingerY)
            updateScrolling()
        }
    }

    /// Where the finger has been since the row lifted, which arms an edge's band.
    @ObservationIgnored private var travel = RailDrag.Travel(from: 0)

    /// Whether a held row is in an edge's band it has gone toward, so the list scrolls a frame at
    /// a time.
    private(set) var isScrolling = false
    /// Called with how far the list scrolled under the held finger, in the same update as the
    /// scroll, so the card and the gap follow in the same frame.
    @ObservationIgnored var onScroll: ((CGFloat) -> Void)?
    /// Where this hold last scrolled the list to, which the scroll view may not have reported
    /// yet: the next step goes on from there, so no distance is counted twice.
    @ObservationIgnored fileprivate var scrolledTo: CGFloat?
    @ObservationIgnored fileprivate var scroll: ScrollGeometry?

    /// The part of the scroll view the list shows in, between the bars.
    fileprivate var visible: ClosedRange<CGFloat>? {
        // The scroll view's frame starts under the top bar, and its container is the area
        // between the bars; the content insets cover the bars it scrolls under.
        guard let scroll else { return nil }
        return 0 ... scroll.containerSize.height
    }

    /// Stops the frame-by-frame scroll at an end of the list, until the finger moves.
    fileprivate func stopAtEnd() {
        isScrolling = false
    }

    private func updateScrolling() {
        let scrolls = isHeld
            && visible.map { speed(in: $0) != 0 } == true
        if scrolls != isScrolling {
            isScrolling = scrolls
        }
    }

    /// How fast the finger asks the list to scroll, in points a second.
    fileprivate func speed(in visible: ClosedRange<CGFloat>) -> CGFloat {
        RailDrag.edgeSpeed(fingerY: fingerY, visible: visible, travel: travel)
    }

    /// Whether `y` in the scroll view's space is outside the list, over a bar or past the screen's
    /// edge.
    func isOutside(_ y: CGFloat) -> Bool {
        visible.map { !$0.contains(y) } ?? false
    }
}

extension EnvironmentValues {
    @Entry var railEdges: RailEdges?
}

private struct RailAutoscroll: ViewModifier {
    @Binding var position: ScrollPosition
    @State private var edges = RailEdges()
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .environment(\.railEdges, edges)
            // The finger is read in the scroll view's own space, so nothing measures where the
            // scroll view is on screen: an `onGeometryChange` here made the scroll geometry
            // update more than once a frame at launch.
            .coordinateSpace(.named(RailDrag.scrollSpace))
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, scroll in
                edges.scroll = scroll
            }
            .background {
                // A frame at a time, only while a held row is in an edge's band.
                if edges.isScrolling {
                    TimelineView(.animation) { timeline in
                        Color.clear.onChange(of: timeline.date) { old, new in
                            step(by: new.timeIntervalSince(old))
                        }
                    }
                }
            }
            .hotReloadable()
    }

    /// Scrolls as far as the finger's depth in an edge's band asks for over `seconds`, stopping
    /// at either end of the list.
    private func step(by seconds: TimeInterval) {
        guard let scroll = edges.scroll, let visible = edges.visible else { return }
        let speed = edges.speed(in: visible)
        guard speed != 0 else { return }
        // A frame that came late moves no further than one at 30 fps would.
        let current = edges.scrolledTo ?? scroll.scrolledY
        let next = min(max(current + speed * min(seconds, 1.0 / 30), 0), scroll.endY)
        guard next != current else { return edges.stopAtEnd() }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(y: next)
        }
        edges.scrolledTo = next
        // Outside the scroll's transaction, so the gap still moves on its own animation.
        edges.onScroll?(next - current)
    }
}

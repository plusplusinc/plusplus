import SwiftUI

extension View {
    /// Lets a row held on a rail inside this scroll view scroll it: held near the top or bottom
    /// of the area the list shows in, the list scrolls, faster the nearer the edge, and the card
    /// stays under the finger as the rows pass under it. Let go outside that area, over a bar,
    /// the row goes back where it was.
    public func railAutoscroll(_ position: Binding<ScrollPosition>) -> some View {
        modifier(RailAutoscroll(position: position))
    }
}

/// What a held row and the scroll view around it share: where the finger is, where the list
/// shows on screen, and how far the list has scrolled under the finger.
@Observable
final class RailEdges {
    /// Whether a row is held, which is when the list may scroll on its own.
    var isHeld = false
    /// The held finger's y on screen.
    @ObservationIgnored var fingerY: CGFloat = 0
    /// Called with how far the list scrolled under the held finger, in the scroll's transaction,
    /// so the card and the gap follow in the same frame.
    @ObservationIgnored var onScroll: ((CGFloat) -> Void)?
    @ObservationIgnored fileprivate var scroll: ScrollGeometry?
    /// The scroll view's top on screen.
    @ObservationIgnored fileprivate var top: CGFloat = 0

    /// The part of the screen the list shows in, between the bars.
    fileprivate var visible: ClosedRange<CGFloat>? {
        // The scroll view's frame starts under the top bar, and its container is the area
        // between the bars; the content insets cover the bars it scrolls under.
        guard let scroll else { return nil }
        return top ... top + scroll.containerSize.height
    }

    /// Whether `y` on screen is outside the list, over a bar or past the screen's edge.
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
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                edges.top = top
            }
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, scroll in
                edges.scroll = scroll
            }
            .background {
                // A frame at a time, only while a row is held.
                if edges.isHeld {
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
        let speed = RailDrag.edgeSpeed(fingerY: edges.fingerY, visible: visible)
        guard speed != 0 else { return }
        // `scrollTo(y:)` counts from the top of the content, not from above the top inset. A
        // frame that came late moves no further than one at 30 fps would.
        let current = scroll.contentOffset.y + scroll.contentInsets.top
        let end = max(scroll.contentSize.height - scroll.containerSize.height, 0)
        let next = min(max(current + speed * min(seconds, 1.0 / 30), 0), end)
        guard next != current else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(y: next)
            edges.onScroll?(next - current)
        }
    }
}

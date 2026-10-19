import SwiftUI

extension View {
    /// Lets a row held on a rail inside this scroll view scroll it: dragged toward the top or
    /// bottom of the area the list shows in, into the band at that edge, the list scrolls, faster
    /// the nearer the edge, and the card stays under the finger as the rows pass under it. Let go
    /// outside that area, over a bar, the row goes back where it was.
    public func railAutoscroll(_ position: Binding<ScrollPosition>) -> some View {
        modifier(RailAutoscroll(position: position))
    }
}

/// What a held row and the scroll view around it share: where the finger is in the scroll view,
/// where the list shows in it, and how far the list has scrolled under the finger.
@Observable
final class RailEdges {
    /// Whether a row is held, which is when the list may scroll on its own.
    @ObservationIgnored private(set) var isHeld = false
    /// The held finger's y in the scroll view's space.
    @ObservationIgnored private(set) var fingerY: CGFloat = 0

    /// Where the finger has been since the row lifted, which arms an edge's band.
    @ObservationIgnored private var travel = RailDrag.Travel(from: 0)

    /// Whether a held row is in an edge's band it has gone toward, so the list scrolls a frame at
    /// a time.
    private(set) var isScrolling = false
    /// Called with how far the list scrolled under the held finger, in the same update as the
    /// scroll, so the card and the gap follow in the same frame.
    @ObservationIgnored fileprivate var onScroll: ((CGFloat) -> Void)?
    /// Where this hold last scrolled the list to, which the scroll view may not have reported
    /// yet: the next step goes on from there, so no distance is counted twice.
    @ObservationIgnored fileprivate var scrolledTo: CGFloat?
    @ObservationIgnored fileprivate var scroll: ScrollGeometry?
    /// Scrolls the list to a `scrollTo(y:)` value, in the transaction it is called in.
    @ObservationIgnored fileprivate var scrollTo: ((CGFloat) -> Void)?

    /// Room added below the list's end, so it can scroll as far as a held row's room above the
    /// rail asks even when it is shorter than the screen. It goes once the row is let go.
    private(set) var roomBelow: CGFloat = 0
    /// The room this hold has opened above the rail, and how far it has scrolled the list for
    /// it (`makeRoom`).
    @ObservationIgnored private var madeRoom: CGFloat = 0
    @ObservationIgnored private var roomScroll: CGFloat = 0
    /// How far the list scrolled past its end, short of none, before any room: negative where
    /// the list is shorter than the area it shows in.
    @ObservationIgnored private var realEnd: CGFloat?
    /// The animation room was last made on, which letting go scrolls back on.
    @ObservationIgnored private var roomAnimation: Animation?

    /// The part of the scroll view the list shows in, between the bars.
    private var visible: ClosedRange<CGFloat>? {
        // The scroll view's frame starts under the top bar, and its container is the area
        // between the bars; the content insets cover the bars it scrolls under.
        guard let scroll else { return nil }
        return 0 ... scroll.containerSize.height
    }

    /// A row lifted with the finger at `y`, in the scroll view's space; `onScroll` is told how
    /// far the list scrolls under it. `room` is the most room above the rail the hold can ask
    /// for (`makeRoom`): where the list is too short to scroll that far, its end moves down now
    /// so it can. Moved in the same moment as the scroll, the end would not yet be laid out
    /// where the scroll goes, and the scroll would stop short of it.
    func lift(at y: CGFloat, room: CGFloat = 0, onScroll: @escaping (CGFloat) -> Void) {
        fingerY = y
        travel = RailDrag.Travel(from: y)
        scrolledTo = nil
        madeRoom = 0
        roomScroll = 0
        realEnd = nil
        if let scroll {
            roomBelow = max(0, room - (scroll.contentSize.height - scroll.containerSize.height))
        }
        self.onScroll = onScroll
        isHeld = true
        updateScrolling()
    }

    /// The held finger moved to `y`.
    func move(to y: CGFloat) {
        fingerY = y
        travel.pass(y)
        updateScrolling()
    }

    /// The row let go: the list stops scrolling for it, and scrolls back by the room it made
    /// above the rail, which closes as it does.
    func letGo() {
        isHeld = false
        onScroll = nil
        updateScrolling()
        let made = roomScroll
        madeRoom = 0
        roomScroll = 0
        realEnd = nil
        guard made != 0, let scrollTo else {
            roomBelow = 0
            return
        }
        let current = scrolledTo ?? scroll?.scrolledY ?? 0
        scrolledTo = nil
        withAnimation(roomAnimation) {
            scrollTo(max(current - made, 0))
        } completion: {
            self.roomBelow = 0
        }
    }

    /// Scrolls the list by `change` in the room above the rail, on `animation`, as the rail opens
    /// or closes that room in the same moment, so the rows stay put on the screen: never above
    /// the list's top, and past its end only as far as `roomBelow`, set on the lift, lets it.
    /// Returns how far it scrolled.
    func makeRoom(_ change: CGFloat, animation: Animation?) -> CGFloat {
        guard isHeld, let scroll, let scrollTo else { return 0 }
        let current = scrolledTo ?? scroll.scrolledY
        let end = realEnd ?? scroll.contentSize.height - scroll.containerSize.height
        realEnd = end
        madeRoom += change
        // The list's end moves down by the room the rail adds, and by `roomBelow`.
        let next = min(max(current + change, 0), end + madeRoom + roomBelow)
        guard next != current else { return 0 }
        roomAnimation = animation
        withAnimation(animation) {
            scrollTo(next)
        }
        scrolledTo = next
        roomScroll += next - current
        return next - current
    }

    /// Stops the frame-by-frame scroll at an end of the list, until the finger moves.
    fileprivate func stopAtEnd() {
        isScrolling = false
    }

    private func updateScrolling() {
        let scrolls = speed != 0
        if scrolls != isScrolling {
            isScrolling = scrolls
        }
    }

    /// How fast the finger asks the list to scroll, in points a second.
    fileprivate var speed: CGFloat {
        guard isHeld else { return 0 }
        return visible
            .map { RailDrag.edgeSpeed(fingerY: fingerY, visible: $0, travel: travel) } ?? 0
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
            .contentMargins(.bottom, edges.roomBelow, for: .scrollContent)
            .environment(\.railEdges, edges)
            // The scroll view's frame, which `visible` and the finger are measured in.
            .coordinateSpace(.named(RailDrag.scrollSpace))
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, scroll in
                edges.scroll = scroll
            }
            .onAppear {
                let position = $position
                edges.scrollTo = { position.wrappedValue.scrollTo(y: $0) }
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
        guard let scroll = edges.scroll else { return }
        let speed = edges.speed
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

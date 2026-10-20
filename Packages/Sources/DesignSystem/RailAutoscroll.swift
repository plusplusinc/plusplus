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
    /// Called with how far the rail moved up the screen in a frame, which moves the card down it
    /// in the same update, so it stays under the finger, and whether the list scrolled for the
    /// finger in an edge's band, which carries the card through the rows.
    @ObservationIgnored private var onScroll: ((CGFloat, Bool) -> Void)?
    /// Where this hold last scrolled the list to, which the scroll view may not have reported
    /// yet: the next step goes on from there, so no distance is counted twice.
    @ObservationIgnored private var scrolledTo: CGFloat?
    @ObservationIgnored fileprivate var scroll: ScrollGeometry?
    /// Scrolls the list to a `scrollTo(y:)` value, in the transaction it is called in.
    @ObservationIgnored fileprivate var scrollTo: ((CGFloat) -> Void)?
    /// Told each time the frame clock that steps the list is read, so a test can see it is read
    /// once a frame.
    @ObservationIgnored var frameRead: ((Date) -> Void)?

    /// The room above the rail a held row asks for (`Rail.roomAbove`), as the rail pads by it
    /// now. It moves toward what is asked a frame at a time, and each frame the list scrolls by
    /// as much in the same update, so the rail, and the card on it, stay where they are on the
    /// screen to the point, and what is above the rail moves up.
    private(set) var room: CGFloat = 0
    /// Whether the room is still moving toward what is asked.
    private(set) var isMakingRoom = false
    @ObservationIgnored private var roomMove = RailRoomMove()
    /// Room added below the list's end, so it can scroll as far as a held row's room above the
    /// rail asks even when it is shorter than the screen. It goes once the room above has closed
    /// with no row held.
    private(set) var roomBelow: CGFloat = 0

    /// The part of the scroll view the list shows in, between the bars.
    private var visible: ClosedRange<CGFloat>? {
        // The scroll view's frame starts under the top bar, and its container is the area
        // between the bars; the content insets cover the bars it scrolls under.
        guard let scroll else { return nil }
        return 0 ... scroll.containerSize.height
    }

    /// Whether the list scrolls a frame at a time, for the finger or the room.
    var isStepping: Bool {
        isScrolling || isMakingRoom
    }

    /// A row lifted with the finger at `y`, in the scroll view's space; `onScroll` is told how
    /// far the rail moves under it. `room` is the most room above the rail the hold can ask for
    /// (`aim(room:)`): where the list is too short to scroll that far, its end moves down now so
    /// it can. Moved in the same moment as the scroll, the end would not yet be laid out where
    /// the scroll goes, and the scroll would stop short of it.
    func lift(
        at y: CGFloat,
        room: CGFloat = 0,
        onScroll: @escaping (_ distance: CGFloat, _ byEdge: Bool) -> Void,
    ) {
        fingerY = y
        travel = RailDrag.Travel(from: y)
        scrolledTo = nil
        if let scroll {
            let end = scroll.contentSize.height - scroll.containerSize.height
            roomBelow = max(roomBelow, room - end)
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

    /// The row let go: the list stops scrolling for it. The room it made above the rail closes as
    /// the rail asks for none (`aim(room:)`).
    func letGo() {
        isHeld = false
        onScroll = nil
        updateScrolling()
        clearRoomBelow()
    }

    /// Gives back the room reserved below the rows once the room above has closed with nothing
    /// held.
    private func clearRoomBelow() {
        if !isMakingRoom, !isHeld, room == 0 {
            roomBelow = 0
        }
    }

    /// Opens or closes the room above the rail to `target`: a frame at a time on
    /// `RailDrag.roomSpring`, or, not `animated`, at once.
    func aim(room target: CGFloat, animated: Bool) {
        guard scroll != nil, scrollTo != nil else {
            roomMove.jump(to: target)
            room = target
            return
        }
        if !isStepping {
            // The list may have been scrolled by hand since this last scrolled it.
            scrolledTo = nil
        }
        if animated {
            roomMove.aim(at: target)
            isMakingRoom = !roomMove.isSettled
        } else {
            roomMove.jump(to: target)
            isMakingRoom = false
            step(edge: 0, grown: target - room)
        }
    }

    /// One frame, `seconds` after the last: the list scrolls as far as the finger's depth in an
    /// edge's band asks, stopping at either end, and the room above the rail moves on.
    fileprivate func step(by seconds: TimeInterval) {
        guard let scroll else { return }
        var edge: CGFloat = 0
        if isScrolling {
            let current = scrolledTo ?? scroll.scrolledY
            // A frame that came late moves no further than one at 30 fps would.
            // Not into the room below, which is there only for the room above the rail: let go,
            // it goes, and a list scrolled into it would jump back.
            let end = max(scroll.endY - roomBelow, current)
            let next = min(max(current + speed * min(seconds, 1.0 / 30), 0), end)
            if next == current {
                // Stops at an end of the list, until the finger moves.
                isScrolling = false
            }
            edge = next - current
        }
        var grown: CGFloat = 0
        if isMakingRoom {
            grown = roomMove.advance(by: seconds) - room
            isMakingRoom = !roomMove.isSettled
        }
        step(edge: edge, grown: grown)
    }

    /// Scrolls the list by `edge` for the finger, and by the room above the rail growing by
    /// `grown`, padded in the same update as the scroll. Whatever the room's scroll falls short
    /// of moves the rail on the screen, and the card back the other way.
    private func step(edge: CGFloat, grown: CGFloat) {
        guard edge != 0 || grown != 0, let scroll, let scrollTo else { return }
        let current = scrolledTo ?? scroll.scrolledY
        let made = RailDrag.roomScroll(
            from: current + edge,
            grown: grown,
            // The end as the scroll view last reported it, with the room below, and as far again
            // as the room grows in this update.
            end: scroll.endY + max(grown, 0),
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            room += grown
            if made.to != current {
                scrollTo(made.to)
            }
        }
        scrolledTo = made.to
        clearRoomBelow()
        // Outside the scroll's transaction, so the gap still moves on its own animation.
        onScroll?(edge - made.railMoves, edge != 0)
    }

    private func updateScrolling() {
        let scrolls = speed != 0
        if scrolls != isScrolling {
            isScrolling = scrolls
        }
    }

    /// How fast the finger asks the list to scroll, in points a second.
    private var speed: CGFloat {
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
                // A frame at a time, only while a held row is in an edge's band, or the room
                // above the rail moves.
                if edges.isStepping {
                    RailFrames(edges: edges)
                }
            }
            .hotReloadable()
    }
}

/// Steps the list once a frame. Its own view, with nothing to change but `edges`, so a step,
/// which scrolls the list and so re-runs the body around it, doesn't read the frame clock again:
/// read again later in the same frame, it can give the next frame's date, and the list would
/// step twice in one frame, which SwiftUI logs as a fault.
private struct RailFrames: View {
    let edges: RailEdges

    var body: some View {
        TimelineView(.animation) { timeline in
            frame(at: timeline.date)
        }
    }

    private func frame(at date: Date) -> some View {
        edges.frameRead?(date)
        return Color.clear.onChange(of: date) { old, new in
            edges.step(by: new.timeIntervalSince(old))
        }
    }
}

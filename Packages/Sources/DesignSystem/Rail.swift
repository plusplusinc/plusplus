import SwiftUI

/// Rows on a rail, one for each element of `data`: a line runs through the rows' nodes, from
/// the first node to the last, above the view at the rail's end, a key with a `plus` icon in the
/// rail column.
///
/// Rows stack with no spacing. Each is made with `railRow()`, which gives it its node, its
/// height, and its own stretch of the line, so nodes fall at an even rhythm whether a row has
/// one line or two, and anything applied to the row, such as swipe actions, carries its node
/// and its stretch of line with it. At rest the stretches abut and read as one line. A row removed
/// fades out quickly.
///
/// The row named by `arriving` is in the rail but takes no space and draws nothing, and the line
/// still ends at the node above. When `arriving` lets it go in a transaction marked
/// `isRailEntry`, it enters (`RailEntry`): its place opens as the line grows down to it, and its
/// node lands in `railJoin`, the color of something joining the rail, then settles to its own
/// color, as its content lands in its own colors. A row let go in any other transaction, or
/// added with no `arriving`, takes that transaction's animation.
///
/// Given `onMove`, a hold on a row's content lifts it into a card under the finger, and a drag
/// opens a gap where it would land, the rows moving aside; a drop calls `onMove` with the slot.
/// Inside a scroll view with `railAutoscroll`, a row dragged toward its edges scrolls it, and one
/// let go over a bar goes back.
///
/// Rows in `links` are joined to the row after them, into a group, a superset, which a loop beside
/// the line marks. A row dragged by its content to a group's edge can land just inside it, the
/// loop wrapping the gap, or just outside; the slot `onMove` gets says which.
///
/// Given `regroup`, a hold on a row's node starts a drag that draws a group instead, the rows
/// staying put: the rows from the held one to the one under the finger sit in one raised field,
/// the held row's card stretched over them, and the loops show what a drop would make, all in
/// their own colors. A drop commits it, and the new group's loop flashes in `railJoin`, as a new
/// node does.
public struct Rail<Data: RandomAccessCollection, Row: View, End: View>: View
    where Data.Element: Identifiable
{
    typealias RowID = Data.Element.ID

    let data: Data
    private let arriving: RowID?
    private let onMove: ((RowID, RailSlot<RowID>) -> Void)?
    let links: Set<RowID>
    let regroup: RailRegroup<RowID>?
    let row: (Data.Element) -> Row
    private let end: End
    /// Drawn at a moment of a drag: how far below its gap the card is, already risen.
    let momentOffset: CGFloat?

    // State and inputs the node hold reads are internal, not private, so it can live in its own
    // files (`Rail+Regroup.swift`, `Rail+Rows.swift`).

    /// The row held and dragged, if any: the rows show in the order they would take if it were
    /// dropped now, and it draws as a card under the finger.
    @State var drag: RailDragState<RowID>?
    /// The row whose node is held, drawing a group, if any.
    @State var regrouping: RailRegroupState<RowID>?
    /// Counts each row's group made by a node's drop, which flashes its loop in `railJoin`.
    @State var flashes: [RowID: Int] = [:]
    /// Where the rows' text is, in the rail's space, so the regroup field's label keeps clear of
    /// it.
    @State var textFrames: [CGRect] = []
    /// How far down each row its node is, at rest.
    @State var nodeInsets: [RowID: CGFloat] = [:]
    /// The rows swiped open, whose groups hide their loops.
    @State var swiped: Set<RowID> = []
    /// The card's top, in the rail's space. It is its own state, so the finger moves it with no
    /// animation even as the same move sends the gap, and the rows, on an animated one.
    @State private var cardTop: CGFloat = 0
    /// Each row's height, read when a drag starts and as it moves, to place the gap. Kept out of
    /// the view's state, so a row's place opening, frame by frame, doesn't redraw the rail.
    @State var heights = RowHeights<RowID>()
    /// Counts heights measured while a row or a node is held, which move its gap and card, or
    /// its field.
    @State var remeasured = 0
    /// The rail column's width, where a press lifts nothing.
    @State private var columnWidth: CGFloat = 0
    /// A light impact: a row lifted or a node held, and a group dropped.
    @State var lifts = 0
    @State var ticks = 0
    /// The scroll view's edges, when it scrolls for a held row (`railAutoscroll`).
    @Environment(\.railEdges) var edges
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObserveHotReload private var hotReload

    /// A rail whose rows a hold lifts and a drag moves, when `onMove` is given: it is called
    /// with the row and where it was dropped, unless that is where it started.
    public init(
        _ data: Data,
        links: Set<Data.Element.ID> = [],
        arriving: Data.Element.ID? = nil,
        onMove: ((Data.Element.ID, RailSlot<Data.Element.ID>) -> Void)? = nil,
        regroup: RailRegroup<Data.Element.ID>? = nil,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.init(
            data,
            links: links,
            arriving: arriving,
            onMove: onMove,
            regroup: regroup,
            drag: nil,
            row: row,
            end: end,
        )
    }

    /// A rail at a moment of a drag, so a preview or a snapshot can draw it.
    init(
        _ data: Data,
        links: Set<RowID> = [],
        arriving: RowID? = nil,
        onMove: ((RowID, RailSlot<RowID>) -> Void)? = nil,
        regroup: RailRegroup<RowID>? = nil,
        drag: RailDragState<RowID>?,
        regrouping: RailRegroupState<RowID>? = nil,
        cardOffset: CGFloat = 0,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.data = data
        self.links = links
        self.arriving = arriving
        self.onMove = onMove
        self.regroup = regroup
        _drag = State(initialValue: drag)
        _regrouping = State(initialValue: regrouping)
        self.row = row
        self.end = end()
        momentOffset = drag == nil ? nil : cardOffset
    }

    public var body: some View {
        let shown = shownRows
        let cardY = drag.map(cardY)
        // The lifted row is in the gap, so the line runs from the first row left on the rail to
        // the last, through the gap where the gap is between them.
        let first = shown.first?.id
        // Until the arriving row enters, the line ends at the node above it.
        let lastOnLine = shown.last { $0.id != arriving }?.id
        let shownLinks = RailLink.links(shown.map(\.id), joined: shownJoined)
        let hiddenLoops = loopsHidden(shown.map(\.id))
        // Held, the rail draws every stroke once, under the rows, rather than each row its own.
        let isHeld = drag != nil || regrouping != nil
        VStack(alignment: .leading, spacing: 0) {
            // Each row learns its place from the rail. Rows taken as a view's subviews could
            // not: a subview resolves in its container's environment, not one set on it.
            ForEach(shown) { item in
                let isArriving = item.id == arriving
                let place = RailPlace(
                    isFirst: item.id == first,
                    isLast: isArriving || item.id == lastOnLine,
                    isArriving: isArriving,
                    isGap: item.id == drag?.lifted,
                    drawsOwnLine: !isHeld,
                    link: shownLinks[item.id] ?? .solo,
                    flashes: flashes[item.id] ?? 0,
                    isLoopHidden: hiddenLoops.contains(item.id),
                )
                // An arriving row's place opens with its entry's shot, so the end view is pushed
                // down as far as the line has grown, on every frame.
                OpeningSpace(progress: isArriving ? 0 : 1) {
                    row(item)
                        .environment(\.railPlace, place)
                        .onPreferenceChange(RailRowSwiped.self) { noteSwipe(item.id, $0) }
                }
                .entry(RailEntry.space(reduceMotion: reduceMotion), value: isArriving)
                // A row's swipe closes when its action runs, so a deleted row slid back to rest
                // as it went. It fades out first instead, while the rows below close the gap.
                // An arriving row draws nothing until its entry, so its fade shows nothing.
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.animation(.snappy(duration: 0.15)),
                ))
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    heights.byID[item.id] = height
                    if isHeld {
                        remeasured += 1
                    }
                }
                .reportingFrame { heights.frames[item.id] = $0 }
                .liftable(
                    isEnabled: (onMove != nil || regroup != nil) && arriving == nil,
                    columnWidth: columnWidth,
                    allowsColumn: regroup != nil,
                    onPhase: { dragged(item.id, $0, at: $1) },
                )
                .reportingNode(of: item.id)
            }
            // Between the last row and the end view, as the design has it.
            end.padding(.top, data.isEmpty ? 0 : Spacing.xxs)
                .reportingFrame { heights.end = $0 }
        }
        .onPreferenceChange(RowTextFrames.self) { textFrames = $0 }
        .onPreferenceChange(RowNodeInsets.self) { noteNodeInsets($0) }
        // While a row or its node is held, the rail's strokes are drawn once, here, under the
        // rows: rows trading places move toward each other, so their own stretches, each moving
        // with its row, would part or overlap until the rows settle, and the loops change shape
        // in one drawing as the rows move. It gives way to the rows' own at once.
        .backgroundPreferenceValue(RowNodes.self) { nodes in
            if isHeld {
                GeometryReader { strokes(nodes, in: $0, cardY: cardY) }
                    .transition(.identity)
            }
        }
        .backgroundPreferenceValue(RailNodes.self) { nodes in
            spanField(nodes)
        }
        .coordinateSpace(.named(RailDrag.space))
        // The card, over the rows it passes and Add exercise. It is placed in the rail's space,
        // where the finger is, not in the row's place, which moves as the gap does.
        .overlayPreferenceValue(RowNodes.self) { nodes in
            if let drag, let cardY {
                GeometryReader { proxy in
                    card(
                        drag,
                        at: cardY,
                        strokes: heldDrawing(drag, nodes, in: proxy, cardY: cardY),
                    )
                }
                .allowsHitTesting(false)
            }
        }
        .background(alignment: .topLeading) {
            // The rail column as a row's node has it, measured at the current text size.
            Image(systemName: "plus")
                .font(.ppButton)
                .railColumn()
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { columnWidth = $0 }
        }
        // Torn down mid-hold, the list stops scrolling for it.
        .onDisappear {
            if drag != nil {
                edges?.letGo()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lifts)
        .sensoryFeedback(RailDrag.slotChange, trigger: ticks)
        .hotReloadable()
    }

    /// Where the card's top is: under the finger, or, for a moment drawn, placed from its gap.
    private func cardY(_ drag: RailDragState<RowID>) -> CGFloat {
        momentOffset.map { gapTop(of: drag) + $0 } ?? cardTop
    }

    /// The top of the gap the held row is over.
    private func gapTop(of drag: RailDragState<RowID>) -> CGFloat {
        gapTop(lifting: drag.lifted, at: drag.slot) ?? 0
    }

    private func dragged(_ id: RowID, _ phase: RailDrag.Phase, at finger: RailDrag.Finger) {
        switch phase {
        case .began:
            guard drag == nil, regrouping == nil else { return }
            if finger.inColumn, regroup != nil {
                return holdNode(id, at: finger)
            }
            guard onMove != nil else { return }
            let candidates = candidates(lifting: id)
            guard let origin = RailDrag.origin(
                of: id,
                in: data.map(\.id),
                candidates: candidates,
                groups: groups,
            ),
                let own = candidates.first(where: { $0.slot == origin })
            else { return }
            cardTop = own.gapTop
            drag = RailDragState(
                lifted: id,
                origin: own.slot,
                slot: own.slot,
                grab: finger.inRail - own.gapTop,
                rows: data.map(\.id),
            )
            lifts += 1
            // The list scrolling under a still finger carries the card through the rows.
            edges?.lift(at: finger.inScrollView) { distance in
                cardTop += distance
                follow(id)
            }
        case .changed:
            if regrouping?.held == id {
                return moveNodeFinger(to: finger)
            }
            guard let held = drag, held.lifted == id else { return }
            cardTop = finger.inRail - held.grab
            edges?.move(to: finger.inScrollView)
            // Over a bar, where a drop sends the row back, the rows show it back where it was.
            let isOverBar = edges?.isOutside(finger.inScrollView) == true
            if isOverBar != held.isOverBar {
                withAnimation(reduceMotion ? nil : RailDrag.gap) { drag?.isOverBar = isOverBar }
            }
            follow(id)
        case .ended, .cancelled:
            if let held = regrouping, held.held == id {
                edges?.letGo()
                let goesBack = phase == .cancelled || edges?.isOutside(finger.inScrollView) == true
                return letGoOfNode(held, goingBack: goesBack)
            }
            guard let released = drag, released.lifted == id, !released.isReleased else { return }
            edges?.letGo()
            // Let go over a bar, or past the screen's edge, the row goes back.
            let goesBack = phase == .cancelled || edges?.isOutside(finger.inScrollView) == true
            settle(released, goingBack: goesBack)
        }
    }

    /// Opens the gap where the card would land.
    private func follow(_ id: RowID) {
        guard let held = drag, held.lifted == id, !held.isReleased else { return }
        let slot = RailDrag.candidate(for: cardTop, in: candidates(lifting: id), current: held.slot)
        guard slot != held.slot else { return }
        withAnimation(reduceMotion ? nil : RailDrag.gap) { drag?.slot = slot }
        // Over a bar the rows don't show the slot, so its changes aren't felt either.
        if !held.isOverBar {
            ticks += 1
        }
    }

    /// Lets the held row go, into its gap or, `goingBack`, back where it started: the card lowers
    /// into the gap as `onMove` reorders the data to match the rows shown, in one transaction, so
    /// no row moves. Back where it started, nothing moves, and the rows close up around it. Once
    /// it has settled, the row draws in its place again.
    private func settle(_ released: RailDragState<RowID>, goingBack: Bool) {
        let slot = goingBack ? released.origin : released.slot
        var settling = released
        settling.slot = slot
        settling.isReleased = true
        settling.isOverBar = false
        let animation = goingBack ? RailDrag.cancel : RailDrag.drop
        withAnimation(reduceMotion ? nil : animation) {
            if slot != released.origin {
                onMove?(released.lifted, slot)
            }
            cardTop = gapTop(lifting: released.lifted, at: slot) ?? cardTop
            drag = settling
        } completion: {
            if drag?.lifted == released.lifted {
                drag = nil
            }
        }
    }
}

/// Rows' heights by id, in a box, so writing one doesn't redraw the rail.
final nonisolated class RowHeights<ID: Hashable> {
    var byID: [ID: CGFloat] = [:]
    /// Each row's frame, and the end view's, in the rail's space.
    var frames: [ID: CGRect] = [:]
    var end: CGRect = .zero
}

extension Animation {
    /// A row going onto or off a rail, and what it moves: quicker than `.snappy`'s default, which
    /// let the rows below a deleted one drift up.
    public static let railChange = Animation.snappy(duration: 0.25)
}

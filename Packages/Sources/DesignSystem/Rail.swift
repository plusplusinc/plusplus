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
/// Rows in `links` are joined to the row after them, into a group, a superset, with a loop beside
/// the line. A row dragged by its content to a group's edge can land just inside it, the loop
/// wrapping the gap, or just outside; the slot `onMove` gets says which. Held still over a plain
/// neighbor, it pairs with it. While a drop would leave the held row in a superset, a well, sunk
/// into the screen, shows that superset as the drop would leave it, the card over it, where the
/// thumb covers its loop; with `railAutoscroll`, the list scrolls to make room for it where the
/// rail has none above, the rail and the card staying still on the screen.
///
/// Given `regroup`, a hold on a row's node starts a drag that draws a group instead, the rows
/// staying put: the rows from the held one to the one under the finger sit in one well, and the
/// loops show what a drop would make, all in their own colors. A drop commits it, and the new
/// group's loop flashes in `railJoin`, as a new node does.
public struct Rail<Data: RandomAccessCollection, Row: View, End: View>: View
    where Data.Element: Identifiable
{
    typealias RowID = Data.Element.ID

    let data: Data
    private let arriving: RowID?
    /// The row a workout is on, whose node shows it in green, pulsing.
    private let current: RowID?
    /// The rows whose sets are all done in a workout, whose nodes show it in purple.
    private let done: Set<RowID>
    /// A pulse from one row's node to another's, as a workout moves on (`RailPulse`).
    private let pulse: RailPulse<RowID>?
    let onMove: ((RowID, RailSlot<RowID>) -> Void)?
    let links: Set<RowID>
    let regroup: RailRegroup<RowID>?
    let row: (Data.Element) -> Row
    private let end: End
    /// Drawn at a moment of a drag: how far below its gap the card is, already risen.
    let momentOffset: CGFloat?
    /// Drawn at a moment of a drag or a node's hold, its well already shown.
    let isMoment: Bool

    // State and inputs the node hold reads are internal, not private, so it can live in its own
    // files (`Rail+Regroup.swift`, `Rail+Rows.swift`).

    /// The row held and dragged, if any: the rows show in the order they would take if it were
    /// dropped now, and it draws as a card under the finger.
    @State var drag: RailDragState<RowID>?
    /// The row whose node is held, drawing a group, if any.
    @State var regrouping: RailRegroupState<RowID>?
    /// Counts each row's group made by a node's drop, which flashes its loop in `railJoin`.
    @State var flashes: [RowID: Int] = [:]
    /// How far down each row its node is, at rest.
    @State var nodeInsets: [RowID: CGFloat] = [:]
    /// Where a row's node is from its top leading corner, as the rows report it, the same on
    /// every row: what places a superset's well.
    @State var railNode: CGPoint?
    /// The rows swiped open, whose groups hide their loops.
    @State var swiped: Set<RowID> = []
    /// The card's top, in the rail's space. It is its own state, so the finger moves it with no
    /// animation even as the same move sends the gap, and the rows, on an animated one.
    @State var cardTop: CGFloat = 0
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
    /// The card resting over a plain neighbor, counting down to pairing with it.
    @State var dwell: RailDwell<RowID>?
    /// A firmer impact: a held row paired with its neighbor.
    @State var pairs = 0
    /// The scroll view's edges, when it scrolls for a held row (`railAutoscroll`).
    @Environment(\.railEdges) var edges
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ScaledLoopPen var pen
    @ObserveHotReload private var hotReload

    /// A rail whose rows a hold lifts and a drag moves, when `onMove` is given: it is called
    /// with the row and where it was dropped, unless that is where it started.
    public init(
        _ data: Data,
        links: Set<Data.Element.ID> = [],
        arriving: Data.Element.ID? = nil,
        current: Data.Element.ID? = nil,
        done: Set<Data.Element.ID> = [],
        pulse: RailPulse<Data.Element.ID>? = nil,
        onMove: ((Data.Element.ID, RailSlot<Data.Element.ID>) -> Void)? = nil,
        regroup: RailRegroup<Data.Element.ID>? = nil,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.init(
            data,
            links: links,
            arriving: arriving,
            current: current,
            done: done,
            pulse: pulse,
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
        current: RowID? = nil,
        done: Set<RowID> = [],
        pulse: RailPulse<RowID>? = nil,
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
        self.current = current
        self.done = done
        self.pulse = pulse
        self.onMove = onMove
        self.regroup = regroup
        _drag = State(initialValue: drag)
        _regrouping = State(initialValue: regrouping)
        self.row = row
        self.end = end()
        momentOffset = drag == nil ? nil : cardOffset
        isMoment = drag != nil || regrouping != nil
    }

    public var body: some View {
        let shown = shownRows
        let cardY = drag.map(cardY)
        let well = drag.flatMap { drag in cardY.flatMap { heldWell(drag, cardY: $0) } }
        // The lifted row is in the gap, so the line runs from the first row left on the rail to
        // the last, through the gap where the gap is between them.
        let first = shown.first?.id
        // Until the arriving row enters, the line ends at the node above it.
        let lastOnLine = shown.last { $0.id != arriving }?.id
        let shownLinks = RailLink.links(shown.map(\.id), joined: shownJoined)
        let hiddenLoops = loopsHidden(shown.map(\.id))
        let shifts = pairShifts(shown.map(\.id))
        let room = drag.map(roomAbove) ?? 0
        // Held, the rail draws every stroke once, under the rows, rather than each row its own.
        let isHeld = drag != nil || regrouping != nil
        RailStack {
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
                    isCurrent: item.id == current,
                    isDone: done.contains(item.id),
                )
                // An arriving row's place opens with its entry's shot, so the end view is pushed
                // down as far as the line has grown, on every frame.
                OpeningSpace(progress: isArriving ? 0 : 1) {
                    row(item)
                        .environment(\.railPlace, place)
                        .onPreferenceChange(RailRowSwiped.self) { noteSwipe(item.id, $0) }
                }
                .entry(RailEntry.space(reduceMotion: reduceMotion), value: isArriving)
                .offset(y: shifts.rows[item.id] ?? 0)
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
                .offset(y: shifts.end)
                .reportingFrame { heights.end = $0 }
        }
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
        .background { spanField() }
        .background { drawnWells(held: well) }
        .coordinateSpace(.named(RailDrag.space))
        // The pulse, over the rows' strokes and nodes, from the nodes as they are on each frame.
        .overlayPreferenceValue(RowNodes.self) { nodes in
            GeometryReader { proxy in
                RailPulseRun(
                    route: pulse.flatMap { route($0, nodes, in: proxy) },
                    run: pulse?.run ?? 0,
                )
            }
        }
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
        // Room above the rows for what a held row's superset shows past the rail's top, which
        // the list scrolls by, so the rows stay put and what is above the rail moves up.
        .padding(.top, edges?.room ?? room)
        .background(alignment: .topLeading) {
            // The rail column as a row's node has it, measured at the current text size.
            Image(systemName: "plus")
                .font(.ppButton)
                .railColumn()
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { columnWidth = $0 }
        }
        // Torn down mid-hold, by a row or its node, the list stops scrolling for it.
        .onDisappear {
            if drag != nil || regrouping != nil {
                edges?.letGo()
            }
            edges?.aim(room: 0, animated: false)
        }
        .task(id: dwell) { await countDown() }
        // Read from the drag's state, so it scrolls as a pair forms, not as the finger wobbles.
        .onChange(of: room) { _, new in edges?.aim(room: new, animated: !reduceMotion) }
        // A row deleted while swiped open, or after its loop flashed, reports nothing more.
        .onChange(of: data.map(\.id)) { _, ids in forget(rowsNotIn: Set(ids)) }
        .sensoryFeedback(.impact(weight: .light), trigger: lifts)
        .sensoryFeedback(RailDrag.slotChange, trigger: ticks)
        .sensoryFeedback(RailDrag.pairFormed, trigger: pairs)
        .hotReloadable()
    }

    /// Where the card's top is: under the finger, or, for a moment drawn, placed from its gap.
    private func cardY(_ drag: RailDragState<RowID>) -> CGFloat {
        momentOffset.map { gapTop(of: drag) + $0 } ?? cardTop
    }

    /// The top of the gap the held row is over.
    func gapTop(of drag: RailDragState<RowID>) -> CGFloat {
        gapTop(lifting: drag.lifted, at: drag.slot) ?? 0
    }
}

extension Rail {
    /// The way `pulse` goes between its nodes: up a superset's loop to its first member, from a
    /// later one in the same superset; straight along the rail otherwise.
    private func route(
        _ pulse: RailPulse<RowID>,
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
    ) -> RailRoute? {
        guard let from = nodes[AnyHashable(pulse.from)].map({ proxy[$0] }),
              let to = nodes[AnyHashable(pulse.to)].map({ proxy[$0] })
        else { return nil }
        let ids = data.map(\.id)
        guard let start = ids.firstIndex(of: pulse.to), let end = ids.firstIndex(of: pulse.from),
              start < end, ids[start ..< end].allSatisfy(links.contains)
        else { return .line(from: from, to: to) }
        return .loop(from: from, to: to, x: pen.runX(nodeX: from.x), radius: pen.radius)
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

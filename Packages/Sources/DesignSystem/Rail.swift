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
public struct Rail<Data: RandomAccessCollection, Row: View, End: View>: View
    where Data.Element: Identifiable
{
    typealias RowID = Data.Element.ID

    private let data: Data
    private let arriving: RowID?
    private let onMove: ((RowID, RailSlot<RowID>) -> Void)?
    private let row: (Data.Element) -> Row
    private let end: End

    /// The row held and dragged, if any: the rows show in the order they would take if it were
    /// dropped now, and it draws as a card under the finger.
    @State private var drag: RailDragState<RowID>?
    /// The card's top, in the rail's space. It is its own state, so the finger moves it with no
    /// animation even as the same move sends the gap, and the rows, on an animated one.
    @State private var cardTop: CGFloat = 0
    /// Each row's height, read when a drag starts and as it moves, to place the gap.
    @State private var heights: [RowID: CGFloat] = [:]
    /// The rail column's width, where a press lifts nothing.
    @State private var columnWidth: CGFloat = 0
    /// The held finger's y in the rail's space.
    @State private var fingerY: CGFloat = 0
    @State private var lifts = 0
    @State private var ticks = 0
    /// The scroll view's edges, when it scrolls for a held row (`railAutoscroll`).
    @Environment(\.railEdges) private var edges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// A rail whose rows a hold lifts and a drag moves, when `onMove` is given: it is called
    /// with the row and where it was dropped, unless that is where it started.
    public init(
        _ data: Data,
        arriving: Data.Element.ID? = nil,
        onMove: ((Data.Element.ID, RailSlot<Data.Element.ID>) -> Void)? = nil,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.init(data, arriving: arriving, onMove: onMove, drag: nil, row: row, end: end)
    }

    /// A rail at a moment of a drag, so a preview or a snapshot can draw it.
    init(
        _ data: Data,
        arriving: RowID? = nil,
        onMove: ((RowID, RailSlot<RowID>) -> Void)? = nil,
        drag: RailDragState<RowID>?,
        cardTop: CGFloat = 0,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.data = data
        self.arriving = arriving
        self.onMove = onMove
        _drag = State(initialValue: drag)
        _cardTop = State(initialValue: cardTop)
        self.row = row
        self.end = end()
    }

    public var body: some View {
        let shown = shownRows
        // The lifted row is in the gap, so the line runs from the first row left on the rail to
        // the last, through the gap where the gap is between them.
        let first = shown.first?.id
        // Until the arriving row enters, the line ends at the node above it.
        let lastOnLine = shown.last { $0.id != arriving }?.id
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
                    isOnDragLine: drag != nil,
                )
                // An arriving row's place opens with its entry's shot, so the end view is pushed
                // down as far as the line has grown, on every frame.
                OpeningSpace(progress: isArriving ? 0 : 1) {
                    row(item).environment(\.railPlace, place)
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
                    heights[item.id] = height
                }
                .liftable(
                    isEnabled: onMove != nil && arriving == nil,
                    columnWidth: columnWidth,
                    onPhase: { dragged(item.id, $0, at: $1) },
                )
            }
            // Between the last row and the end view, as the design has it.
            end.padding(.top, data.isEmpty ? 0 : Spacing.xxs)
        }
        // While a row is held, the line is drawn once, here, under the rows: rows trading places
        // move toward each other, so their own stretches, each moving with its row, would part at
        // the pair's outer edges until the rows settle.
        .backgroundPreferenceValue(RailNodes.self) { nodes in
            if let drag {
                DragLine(
                    nodes: nodes,
                    cardOffset: cardTop - (gapTop(lifting: drag.lifted, at: drag.slot) ?? cardTop),
                    isGapFirst: shown.first?.id == drag.lifted,
                    isGapLast: shown.last?.id == drag.lifted,
                )
            }
        }
        .coordinateSpace(.named(RailDrag.space))
        // The card, over the rows it passes and Add exercise. It is placed in the rail's space,
        // where the finger is, not in the row's place, which moves as the gap does.
        .overlay(alignment: .top) { card }
        .background(alignment: .topLeading) {
            // The rail column as a row's node has it, measured at the current text size.
            Image(systemName: "plus")
                .font(.ppButton)
                .railColumn()
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { columnWidth = $0 }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lifts)
        .sensoryFeedback(RailDrag.slotChange, trigger: ticks)
        .hotReloadable()
    }

    /// The rows in the order they show: with a row held, the order it would make if dropped now.
    private var shownRows: [Data.Element] {
        guard let drag else { return Array(data) }
        let byID = Dictionary(data.map { ($0.id, $0) }) { first, _ in first }
        return RailDrag.order(data.map(\.id), moving: drag.lifted, to: drag.slot)
            .compactMap { byID[$0] }
    }

    private func candidates(lifting lifted: RowID) -> [RailDrag.Candidate<RowID>] {
        RailDrag.candidates(rows: data.map { ($0.id, heights[$0.id] ?? 0) }, lifted: lifted)
    }

    /// The held row drawn again as a card, its top at `cardTop`. It rises as it appears and
    /// lowers as it settles; while held, it follows the finger with no animation, whatever
    /// animation moves the rows.
    @ViewBuilder private var card: some View {
        if let drag, let item = data.first(where: { $0.id == drag.lifted }) {
            row(item)
                // As tall as in the rows, where the scroll view proposes no height, not as tall
                // as the rail it is over.
                .fixedSize(horizontal: false, vertical: true)
                .modifier(CardLook(isReleased: drag.isReleased))
                .offset(y: cardTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The top of the gap at `slot`, where the card rests when it is let go there.
    private func gapTop(lifting lifted: RowID, at slot: RailSlot<RowID>) -> CGFloat? {
        candidates(lifting: lifted).first { $0.slot == slot }?.gapTop
    }

    private func dragged(_ id: RowID, _ phase: RailDrag.Phase, at finger: RailDrag.Finger) {
        switch phase {
        case .began:
            guard drag == nil, let index = data.firstIndex(where: { $0.id == id }) else { return }
            let own = candidates(lifting: id)[data.distance(from: data.startIndex, to: index)]
            cardTop = own.gapTop
            fingerY = finger.inRail
            drag = RailDragState(
                lifted: id,
                origin: own.slot,
                slot: own.slot,
                grab: finger.inRail - own.gapTop,
            )
            lifts += 1
            edges?.fingerY = finger.onScreen
            // The list scrolling under a still finger moves the finger through the rows.
            edges?.onScroll = { distance in
                fingerY += distance
                follow(id)
            }
            edges?.isHeld = true
        case .changed:
            guard drag?.lifted == id else { return }
            fingerY = finger.inRail
            edges?.fingerY = finger.onScreen
            follow(id)
        case .ended:
            guard let dropped = drag, dropped.lifted == id, !dropped.isReleased else { return }
            letGo()
            // Let go over a bar, or past the screen's edge, the row goes back.
            if edges?.isOutside(finger.onScreen) == true {
                return settle(dropped, at: dropped.origin, with: RailDrag.cancel) { }
            }
            settle(dropped, at: dropped.slot, with: RailDrag.drop) {
                if dropped.slot != dropped.origin {
                    onMove?(id, dropped.slot)
                }
            }
        case .cancelled:
            guard let cancelled = drag, cancelled.lifted == id, !cancelled.isReleased
            else { return }
            letGo()
            settle(cancelled, at: cancelled.origin, with: RailDrag.cancel) { }
        }
    }

    /// Puts the held card under the finger, and opens the gap where it would land.
    private func follow(_ id: RowID) {
        guard let held = drag, held.lifted == id, !held.isReleased else { return }
        cardTop = fingerY - held.grab
        let slot = RailDrag.candidate(for: cardTop, in: candidates(lifting: id), current: held.slot)
        guard slot != held.slot else { return }
        withAnimation(reduceMotion ? nil : RailDrag.gap) { drag?.slot = slot }
        ticks += 1
    }

    /// Stops the list scrolling for the finger.
    private func letGo() {
        edges?.isHeld = false
        edges?.onScroll = nil
    }

    /// Lets the held row go at `slot`: the card lowers into the gap there as `move` reorders the
    /// data to match the rows shown, in one transaction, so no row moves. Back where it started,
    /// the rows close up around it. Once it has settled, the row draws in its place again.
    private func settle(
        _ released: RailDragState<RowID>,
        at slot: RailSlot<RowID>,
        with animation: Animation,
        move: () -> Void,
    ) {
        var settling = released
        settling.slot = slot
        settling.isReleased = true
        withAnimation(reduceMotion ? nil : animation) {
            move()
            cardTop = gapTop(lifting: released.lifted, at: slot) ?? cardTop
            drag = settling
        } completion: {
            if drag?.lifted == released.lifted {
                drag = nil
            }
        }
    }
}

extension Animation {
    /// A row going onto or off a rail, and what it moves: quicker than `.snappy`'s default, which
    /// let the rows below a deleted one drift up.
    public static let railChange = Animation.snappy(duration: 0.25)
}

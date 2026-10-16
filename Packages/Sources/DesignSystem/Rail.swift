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
    /// The row just dropped, which stays over the others while it settles.
    @State private var settling: RowID?
    /// Each row's height, read when a drag starts and as it moves, to place the gap.
    @State private var heights: [RowID: CGFloat] = [:]
    /// The rail column's width, where a press lifts nothing.
    @State private var columnWidth: CGFloat = 0
    @State private var lifts = 0
    @State private var ticks = 0
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
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.data = data
        self.arriving = arriving
        self.onMove = onMove
        _drag = State(initialValue: drag)
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
        let offset = liftOffset
        VStack(alignment: .leading, spacing: 0) {
            // Each row learns its place from the rail. Rows taken as a view's subviews could
            // not: a subview resolves in its container's environment, not one set on it.
            ForEach(shown) { item in
                let isArriving = item.id == arriving
                let isLifted = item.id == drag?.lifted
                let place = RailPlace(
                    isFirst: item.id == first,
                    isLast: isArriving || item.id == lastOnLine,
                    isArriving: isArriving,
                    lift: isLifted ? offset : nil,
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
                // The card draws over the rows it passes, and Add exercise.
                .zIndex(isLifted || item.id == settling ? 1 : 0)
                .liftable(
                    isEnabled: onMove != nil && arriving == nil,
                    columnWidth: columnWidth,
                    onPhase: { dragged(item.id, $0, at: $1) },
                )
            }
            // Between the last row and the end view, as the design has it.
            end.padding(.top, data.isEmpty ? 0 : Spacing.xxs)
        }
        .coordinateSpace(.named(RailDrag.space))
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
        .sensoryFeedback(.selection, trigger: ticks)
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

    /// How far the card is drawn from its place in the gap: wherever the gap moves, the card
    /// stays under the finger.
    private var liftOffset: CGFloat {
        guard let drag,
              let gap = candidates(lifting: drag.lifted).first(where: { $0.slot == drag.slot })
        else { return 0 }
        return drag.cardTop - gap.gapTop
    }

    private func dragged(_ id: RowID, _ phase: RailDrag.Phase, at fingerY: CGFloat) {
        switch phase {
        case .began:
            guard drag == nil, let index = data.firstIndex(where: { $0.id == id }) else { return }
            let own = candidates(lifting: id)[data.distance(from: data.startIndex, to: index)]
            withAnimation(reduceMotion ? nil : RailDrag.lift) {
                drag = RailDragState(
                    lifted: id,
                    origin: own.slot,
                    slot: own.slot,
                    cardTop: own.gapTop,
                    grab: fingerY - own.gapTop,
                )
            }
            lifts += 1
        case .changed:
            guard var moved = drag, moved.lifted == id else { return }
            moved.cardTop = fingerY - moved.grab
            moved.slot = RailDrag.candidate(
                for: moved.cardTop,
                in: candidates(lifting: id),
                current: moved.slot,
            )
            guard moved.slot != drag?.slot else {
                drag = moved
                return
            }
            withAnimation(reduceMotion ? nil : RailDrag.gap) { drag = moved }
            ticks += 1
        case .ended:
            guard let dropped = drag, dropped.lifted == id else { return }
            settle(dropped, with: RailDrag.drop) {
                if dropped.slot != dropped.origin {
                    onMove?(id, dropped.slot)
                }
            }
        case .cancelled:
            guard let cancelled = drag, cancelled.lifted == id else { return }
            settle(cancelled, with: RailDrag.cancel) { }
        }
    }

    /// Lets the held row go: the card settles into the gap as `move` reorders the data to match
    /// it, in one transaction, so nothing else moves. Back where it started, the gap closes.
    private func settle(
        _ released: RailDragState<RowID>,
        with animation: Animation,
        move: () -> Void,
    ) {
        settling = released.lifted
        withAnimation(reduceMotion ? nil : animation) {
            move()
            drag = nil
        } completion: {
            if settling == released.lifted {
                settling = nil
            }
        }
    }
}

extension Animation {
    /// A row going onto or off a rail, and what it moves: quicker than `.snappy`'s default, which
    /// let the rows below a deleted one drift up.
    public static let railChange = Animation.snappy(duration: 0.25)
}

/// Where a row sits on its rail: the line starts at the first row's node and ends at the last's.
/// An arriving row holds its place, drawn empty, until it enters. A lifted row's place is the
/// gap, and its node and content draw as a card `lift` points below it.
struct RailPlace {
    var isFirst = true
    var isLast = true
    var isArriving = false
    var lift: CGFloat?
}

extension EnvironmentValues {
    @Entry var railPlace = RailPlace()
}

/// A row's node, centered in the rail column on the row's first line, as the key's icon is: the
/// icon, held invisibly in the column, gives it the key's width and baseline at every text size.
private struct RailNode: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        let pop = RailEntry.pop(reduceMotion: reduceMotion)
        let landing = RailEntry.popStart(reduceMotion: reduceMotion)
        Image(systemName: "plus")
            .font(.ppButton)
            .hidden()
            .railColumn()
            .overlay {
                Circle()
                    .joiningRail(
                        when: place.isArriving,
                        settlingTo: place.lift == nil ? .borderStrong : .textPrimary,
                    )
                    .frame(width: size, height: size)
                    .anchorPreference(key: NodeCenter.self, value: .center) { $0 }
                    // It pops from the line's tip as the line lands: shown at the line's width
                    // and grown to its own size in the same moment.
                    .scaleEffect(place.isArriving ? lineWidth / size : 1)
                    .entry(pop, value: place.isArriving)
                    .scaleEffect(place.isArriving ? 0 : 1)
                    .entry(RailEntry.step(at: landing), value: place.isArriving)
            }
            .accessibilityHidden(true)
            .hotReloadable()
    }
}

/// Where a row's node's center is, so the row's stretch of line can run through it.
private struct NodeCenter: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

private struct RailRow: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        let isLifted = place.lift != nil
        let (offset, scale, angle) = (
            place.lift ?? 0,
            isLifted ? RailDrag.liftedScale : 1,
            isLifted ? RailDrag.liftedRotation : .zero,
        )
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RailNode()
            content
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: minHeight, alignment: .top)
                .opacity(place.isArriving ? 0 : 1)
                .offset(y: place.isArriving && !reduceMotion ? -Spacing.xs : 0)
                .entry(
                    RailEntry.content(reduceMotion: reduceMotion),
                    value: place.isArriving,
                )
                .committing(when: place.isArriving)
        }
        .background { LiftedCard(isLifted: isLifted) }
        // A visual effect moves the card without moving the row's geometry, so its line stays
        // in the gap, running through where its node was.
        .visualEffect { content, _ in
            content.scaleEffect(scale).rotationEffect(angle).offset(y: offset)
        }
        // The row's stretch of line, top edge to bottom edge through its node, or from the node
        // on the first row and to it on the last, drawn as part of the row so it moves with it.
        // It is drawn in two, above and below the node, so the parts an entry adds can each grow
        // on their own stretch of the shot while the rest stays as it was.
        .backgroundPreferenceValue(NodeCenter.self) { center in
            GeometryReader { proxy in
                if let center {
                    // An anchor reads where the node is drawn, on the card when lifted; the
                    // line runs through where it rests.
                    let node = RailDrag.resting(
                        proxy[center],
                        in: proxy.size,
                        offset: offset,
                        scale: scale,
                        angle: angle,
                    )
                    let top = place.isFirst ? node.y : 0
                    let above = place.isArriving ? top : node.y
                    let below = place.isLast ? node.y : proxy.size.height
                    let split = RailEntry.split(height: proxy.size.height, node: node.y)
                    Rectangle()
                        .fill(.pp(.rail))
                        .frame(width: lineWidth, height: above - top)
                        .position(x: node.x, y: (top + above) / 2)
                        .entry(
                            RailEntry.shot(from: split, to: 1, reduceMotion: reduceMotion),
                            value: place.isArriving,
                        )
                    Rectangle()
                        .fill(.pp(.rail))
                        .frame(width: lineWidth, height: below - node.y)
                        .position(x: node.x, y: (node.y + below) / 2)
                        .entry(
                            RailEntry.shot(from: 0, to: split, reduceMotion: reduceMotion),
                            value: place.isLast,
                        )
                }
            }
        }
        .hotReloadable()
    }
}

/// The rail column's width at the default text size.
private let railColumnWidth: CGFloat = 44

/// The line's width at the default text size: one value, so a new node pops from the line's tip.
private let railLineWidth: CGFloat = 2

extension View {
    /// A row on a rail: its node in the rail column, then its content from the top, inset as the
    /// design has it, in a row at least as tall as two lines, so a one-line row keeps the rhythm
    /// of a two-line one.
    public func railRow() -> some View {
        modifier(RailRow())
    }

    /// The rail column: the leading strip where rows put their nodes and a key its icon. At
    /// large text sizes it grows with what it holds, keeping an inset, rather than clipping it.
    func railColumn() -> some View {
        padding(.horizontal, Spacing.sm).frame(minWidth: railColumnWidth)
    }
}

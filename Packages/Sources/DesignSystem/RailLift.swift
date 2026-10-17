import SwiftUI

/// A moment of a drag on a rail.
struct RailDragState<ID: Hashable> {
    var lifted: ID
    /// The slot the row was lifted from, where dropping it changes nothing.
    var origin: RailSlot<ID>
    /// Where the gap is open.
    var slot: RailSlot<ID>
    /// How far below the row's top the finger holds it.
    var grab: CGFloat
    /// Let go, and settling into the gap.
    var isReleased = false
    /// The finger is over a bar, or past the screen's edge, where letting go sends the row back.
    var isOverBar = false

    /// The slot the rows show: the gap's, or, over a bar, where the row started, since a drop
    /// there sends it back.
    var shownSlot: RailSlot<ID> {
        isOverBar ? origin : slot
    }
}

extension View {
    /// A hold on this row lifts it, on iOS. A press in the rail column, on the node, holds the
    /// node when `allowsColumn`, and otherwise does nothing.
    @ViewBuilder
    func liftable(
        isEnabled: Bool,
        columnWidth: CGFloat,
        allowsColumn: Bool,
        onPhase: @escaping (RailDrag.Phase, RailDrag.Finger) -> Void,
    ) -> some View {
        #if os(iOS)
        gesture(RailLiftGesture(
            isEnabled: isEnabled,
            columnWidth: columnWidth,
            allowsColumn: allowsColumn,
            onPhase: onPhase,
        ))
        #else
        self
        #endif
    }
}

/// The held row's card: it appears at rest over its row and rises, its own size, its node in the
/// color of the text. Over its fill it draws the rail's strokes behind it, `strokes`, cut to its
/// shape, as though it were clear, so whatever the card's offset from its gap, card and rail line
/// up and nothing shows twice; it draws no stroke of its own. Released, it lowers to look like the
/// row at rest.
struct CardLook: ViewModifier {
    let isReleased: Bool
    /// The rail's drawing, and the card's top in the rail's space, which places it.
    let strokes: RailDrawing?
    let top: CGFloat
    @State private var hasRisen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// `hasRisen` draws it already risen, for a preview or a snapshot of a moment of a drag.
    init(isReleased: Bool, hasRisen: Bool = false, strokes: RailDrawing? = nil, top: CGFloat = 0) {
        self.isReleased = isReleased
        self.strokes = strokes
        self.top = top
        _hasRisen = State(initialValue: hasRisen)
    }

    func body(content: Content) -> some View {
        let isRaised = hasRisen && !isReleased
        content
            .environment(\.railPlace, RailPlace(drawsOwnLine: false, isRaised: isRaised))
            .backgroundPreferenceValue(RailNodes.self) { nodes in
                if let node = nodes.first {
                    LiftedCard(node: node, isLifted: isRaised, strokes: strokes, top: top)
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : RailDrag.lift) { hasRisen = true }
            }
            .hotReloadable()
    }
}

/// A held row's card: `CardFill` behind the row, as tall as it, with a soft shadow all around
/// that fades in and out with it. At rest, it is not drawn.
struct LiftedCard: View {
    let node: Anchor<CGPoint>
    let isLifted: Bool
    var strokes: RailDrawing?
    /// The card's top in the rail's space. The drawing is moved up by it rather than drawn from
    /// moved nodes, so the finger moving the card leaves the drawing's own animation running.
    var top: CGFloat = 0
    @ObserveHotReload private var hotReload

    var body: some View {
        GeometryReader { proxy in
            CardFill(node: proxy[node], size: proxy.size)
                .shadow(color: .pp(.shadow), radius: RailDrag.liftedShadow)
            strokes?
                .offset(y: -top)
                .mask { CardFill(node: proxy[node], size: proxy.size) }
        }
        .opacity(isLifted ? 1 : 0)
        .hotReloadable()
    }
}

/// The raised fill of a held row's card, with no shadow or border, behind a row or a stretch of
/// rows, `size` big, whose first node is at `node`, from its top leading corner. The node sits as
/// far in from the fill's leading edge as from its top, and its corners are close to concentric
/// with the node: their radius is that inset plus the node's. It is centered across `size`, so on
/// a screen whose rows are, its edges are as far from the screen's, and a row's content stops that
/// inset short of its trailing edge.
struct CardFill: View {
    let node: CGPoint
    let size: CGSize
    @ScaledMetric(relativeTo: .body) private var nodeSize = railNodeSize
    @ObserveHotReload private var hotReload

    var body: some View {
        let radius = nodeSize / 2
        let inset = node.y - radius
        let leading = node.x - radius - inset
        // Continuous, like the app's other shapes, at the cost of sitting about a point off true
        // concentric with the node.
        RoundedRectangle(cornerRadius: inset + radius, style: .continuous)
            .fill(.pp(.surfaceRaised))
            .frame(width: max(size.width - 2 * leading, 0), height: size.height)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .offset(x: leading)
            .hotReloadable()
    }
}

/// Each row's node's center on a rail, by the row's id.
struct RowNodes: PreferenceKey {
    static let defaultValue: [AnyHashable: Anchor<CGPoint>] = [:]

    static func reduce(
        value: inout [AnyHashable: Anchor<CGPoint>],
        nextValue: () -> [AnyHashable: Anchor<CGPoint>],
    ) {
        value.merge(nextValue()) { first, _ in first }
    }
}

/// How far down each row its node is, by the row's id.
struct RowNodeInsets: PreferenceKey {
    static let defaultValue: [AnyHashable: CGFloat] = [:]

    static func reduce(
        value: inout [AnyHashable: CGFloat],
        nextValue: () -> [AnyHashable: CGFloat],
    ) {
        value.merge(nextValue()) { first, _ in first }
    }
}

/// Every node's center in a view, in order: on a rail, the rows', which place the regroup field,
/// and each row's own, read by id (`RowNodes`); on a card, its own.
struct RailNodes: PreferenceKey {
    static let defaultValue: [Anchor<CGPoint>] = []

    static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
        value += nextValue()
    }
}

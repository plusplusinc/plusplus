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

/// The held row's card: it appears at rest over its row and rises, turned a little but its own
/// size, so its stretch of line and its loop stay on the rail's, its node in the color of the
/// text. Released, it lowers to look like the row at rest.
struct CardLook: ViewModifier {
    let isReleased: Bool
    /// Where its gap is in a group, whose loop it draws.
    let link: RailLink
    /// Whether its gap is at the rail's top or bottom, where its stretch of line ends at its node.
    let isFirst: Bool
    let isLast: Bool
    @State private var hasRisen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// `hasRisen` draws it already risen, for a preview or a snapshot of a moment of a drag.
    init(
        isReleased: Bool,
        hasRisen: Bool = false,
        link: RailLink = .solo,
        isFirst: Bool = false,
        isLast: Bool = false,
    ) {
        self.isReleased = isReleased
        self.link = link
        self.isFirst = isFirst
        self.isLast = isLast
        _hasRisen = State(initialValue: hasRisen)
    }

    func body(content: Content) -> some View {
        let isRaised = hasRisen && !isReleased
        content
            .environment(
                \.railPlace,
                RailPlace(isFirst: isFirst, isLast: isLast, isRaised: isRaised, link: link),
            )
            .backgroundPreferenceValue(RailNodes.self) { nodes in
                if let node = nodes.first {
                    LiftedCard(node: node, isLifted: isRaised)
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
    @ObserveHotReload private var hotReload

    var body: some View {
        GeometryReader { proxy in
            CardFill(node: proxy[node], size: proxy.size)
                .shadow(color: .pp(.shadow), radius: RailDrag.liftedShadow)
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

/// Every node's center on a rail, from the first row to the last, so the line can be drawn once
/// from the first to the last while a row is held.
struct RailNodes: PreferenceKey {
    static let defaultValue: [Anchor<CGPoint>] = []

    static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
        value += nextValue()
    }
}

/// The line from the first node to the last, drawn once under the rows while one is held. Its
/// ends are where the nodes are once the rows settle, and they move in the gap's transaction.
///
/// With the gap at an end of the rail, its node is hidden and the card is over it, a little above
/// or below as the finger has it. The line ends at the card's node instead, which the card's own
/// stretch of line meets: moved in from that end, the card leaves no stub past its edge, and moved
/// out past it, no break between its edge and the gap's node.
struct DragLine: View {
    let nodes: [Anchor<CGPoint>]
    /// How far below its gap the card is.
    let cardOffset: CGFloat
    let isGapFirst: Bool
    let isGapLast: Bool
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ObserveHotReload private var hotReload

    var body: some View {
        GeometryReader { proxy in
            if let first = nodes.first, let last = nodes.last {
                let top = proxy[first].y + (isGapFirst ? cardOffset : 0)
                let bottom = proxy[last].y + (isGapLast ? cardOffset : 0)
                Rectangle()
                    .fill(.pp(.rail))
                    .frame(width: lineWidth, height: max(bottom - top, 0))
                    .position(x: proxy[first].x, y: (top + bottom) / 2)
            }
        }
        .hotReloadable()
    }
}

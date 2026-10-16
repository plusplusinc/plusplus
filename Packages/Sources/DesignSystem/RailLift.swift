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
    /// A hold on this row lifts it, on iOS; a press in the rail column lifts nothing.
    @ViewBuilder
    func liftable(
        isEnabled: Bool,
        columnWidth: CGFloat,
        onPhase: @escaping (RailDrag.Phase, RailDrag.Finger) -> Void,
    ) -> some View {
        #if os(iOS)
        gesture(RailLiftGesture(
            isEnabled: isEnabled,
            columnWidth: columnWidth,
            onPhase: onPhase,
        ))
        #else
        self
        #endif
    }
}

/// The held row's card: it appears at rest over its row and rises, a little larger and turned,
/// its node in the color of the text. Released, it lowers to look like the row at rest.
struct CardLook: ViewModifier {
    let isReleased: Bool
    @State private var hasRisen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// `hasRisen` draws it already risen, for a preview or a snapshot of a moment of a drag.
    init(isReleased: Bool, hasRisen: Bool = false) {
        self.isReleased = isReleased
        _hasRisen = State(initialValue: hasRisen)
    }

    func body(content: Content) -> some View {
        let isRaised = hasRisen && !isReleased
        content
            .environment(\.railPlace, RailPlace(isCard: true, isRaised: isRaised))
            .backgroundPreferenceValue(RailNodes.self) { nodes in
                if let node = nodes.first {
                    LiftedCard(node: node, isLifted: isRaised)
                }
            }
            .scaleEffect(isRaised ? RailDrag.liftedScale : 1)
            .rotationEffect(isRaised ? RailDrag.liftedRotation : .zero)
            .onAppear {
                withAnimation(reduceMotion ? nil : RailDrag.lift) { hasRisen = true }
            }
            .hotReloadable()
    }
}

/// A held row's card: a raised fill, with no shadow or border. Its node sits as far in from the
/// leading edge as from the top, and its corners are close to concentric with the node: their
/// radius is that inset plus the node's. It is centered on the row, so on a screen whose rows are,
/// its edges are as far from the screen's, and the row's content stops that inset short of its
/// trailing edge. It is as tall as the row. At rest, it is not drawn.
struct LiftedCard: View {
    let node: Anchor<CGPoint>
    let isLifted: Bool
    @ScaledMetric(relativeTo: .body) private var nodeSize = railNodeSize
    @ObserveHotReload private var hotReload

    var body: some View {
        GeometryReader { proxy in
            let center = proxy[node]
            let radius = nodeSize / 2
            let inset = center.y - radius
            let leading = center.x - radius - inset
            let trailing = proxy.size.width - leading
            // Continuous, like the app's other shapes, at the cost of sitting about a point off
            // true concentric with the node.
            RoundedRectangle(cornerRadius: inset + radius, style: .continuous)
                .fill(.pp(.surfaceRaised))
                .frame(width: trailing - leading, height: proxy.size.height)
                .offset(x: leading)
        }
        .opacity(isLifted ? 1 : 0)
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
/// or below as the finger has it. Moved in from that end, the card would leave a stub of line
/// past its edge, so the line ends at the card's node instead: it never shows past the card.
struct DragLine: View {
    let nodes: [Anchor<CGPoint>]
    /// How far below its gap the card is.
    var cardOffset: CGFloat = 0
    var isGapFirst = false
    var isGapLast = false
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ObserveHotReload private var hotReload

    var body: some View {
        GeometryReader { proxy in
            if let first = nodes.first, let last = nodes.last {
                let top = proxy[first].y + (isGapFirst ? max(cardOffset, 0) : 0)
                let bottom = proxy[last].y + (isGapLast ? min(cardOffset, 0) : 0)
                Rectangle()
                    .fill(.pp(.rail))
                    .frame(width: lineWidth, height: max(bottom - top, 0))
                    .position(x: proxy[first].x, y: (top + bottom) / 2)
            }
        }
        .hotReloadable()
    }
}

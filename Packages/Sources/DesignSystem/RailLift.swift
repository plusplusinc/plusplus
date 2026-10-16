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
        onPhase: @escaping (RailDrag.Phase, CGFloat) -> Void,
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
    @State private var hasRisen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isRaised = hasRisen && !isReleased
        content
            .environment(\.railPlace, RailPlace(isCard: true, isRaised: isRaised))
            .background { LiftedCard(isLifted: isRaised) }
            .scaleEffect(isRaised ? RailDrag.liftedScale : 1)
            .rotationEffect(isRaised ? RailDrag.liftedRotation : .zero)
            .onAppear {
                withAnimation(reduceMotion ? nil : RailDrag.lift) { hasRisen = true }
            }
    }
}

/// A held row's card: a raised fill, with no shadow or border, that bleeds past the row on both
/// sides. At rest, it is not drawn.
struct LiftedCard: View {
    let isLifted: Bool
    @ObserveHotReload private var hotReload

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card)
            .fill(.pp(.surfaceRaised))
            .padding(.horizontal, -Spacing.sm)
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
struct DragLine: View {
    let nodes: [Anchor<CGPoint>]
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth

    var body: some View {
        GeometryReader { proxy in
            if let first = nodes.first, let last = nodes.last {
                let (top, bottom) = (proxy[first], proxy[last])
                Rectangle()
                    .fill(.pp(.rail))
                    .frame(width: lineWidth, height: max(bottom.y - top.y, 0))
                    .position(x: top.x, y: (top.y + bottom.y) / 2)
            }
        }
    }
}

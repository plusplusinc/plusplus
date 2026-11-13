import SwiftUI

/// A moment of a drag on a rail.
struct RailDragState<ID: Hashable> {
    var lifted: ID
    /// The slot the row was lifted from, where dropping it changes nothing.
    var origin: RailSlot<ID>
    /// Where the gap is open.
    var slot: RailSlot<ID>
    /// The card rested over a plain neighbor, and `slot` pairs the two.
    var isPaired = false
    /// While paired, how far the partner, and the rows past it, move out from under the card: as
    /// far as the card lay over it when the pair formed, fixed while the pair holds, so they stay
    /// still as the thumb settles.
    var shift: CGFloat = 0
    /// How far below the row's top the finger holds it.
    var grab: CGFloat
    /// Let go, and settling into the gap.
    var isReleased = false
    /// The finger is over a bar, or past the screen's edge, where letting go sends the row back.
    var isOverBar = false
    /// The rows in order when it was lifted, which name each row's node in the rail's drawing
    /// through the drop, as the rows change order.
    var rows: [ID] = []

    /// The slot the rows show: the gap's, or, over a bar, where the row started, since a drop
    /// there sends it back.
    var shownSlot: RailSlot<ID> {
        isOverBar ? origin : slot
    }
}

extension View {
    /// A hold on this row lifts it, on iOS. A press in the rail column, on the node, holds the
    /// node when `allowsColumn`, and otherwise does nothing.
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
/// color of the text. Over its fill it draws the rail's strokes behind it, `strokes`, as though it
/// were clear, so whatever the card's offset from its gap, card and rail line up and nothing shows
/// twice; it draws no stroke of its own. Past its edges it draws them over its shadow too, as
/// `LiftedCard` says. Released, it lowers to look like the row at rest.
///
/// It lifts by its fill and shadow alone, level and unscaled, with no border or grip: tilted or
/// grown, its node would leave the rail's line, and the strokes it draws would no longer meet
/// the rail's at its edges.
struct CardLook: ViewModifier {
    let isReleased: Bool
    /// The rail's drawing, and the card's top in the rail's space, which places it.
    let strokes: HeldRailDrawing?
    let top: CGFloat
    /// Where the rail under the card shows no strokes, in the rail's space (`Rail.cutouts`).
    let holes: [CGRect]
    @State private var hasRisen: Bool
    /// How far down a plain row its node is (`PlainRowNode`), which shapes the card. Measured on
    /// the card, at the card's own place on the pixel grid, so a plain row's card is shaped from
    /// exactly its own node.
    @State private var plainNodeY: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `hasRisen` draws it already risen, for a preview or a snapshot of a moment of a drag.
    init(
        isReleased: Bool,
        hasRisen: Bool = false,
        strokes: HeldRailDrawing? = nil,
        top: CGFloat = 0,
        holes: [CGRect] = [],
    ) {
        self.isReleased = isReleased
        self.strokes = strokes
        self.top = top
        self.holes = holes
        _hasRisen = State(initialValue: hasRisen)
    }

    func body(content: Content) -> some View {
        let isRaised = hasRisen && !isReleased
        content
            .environment(\.railPlace, RailPlace(drawsOwnLine: false, isRaised: isRaised))
            .backgroundPreferenceValue(RailNodes.self) { nodes in
                // Not drawn until a plain row's node is measured: from the row's own node, the
                // current exercise's card would show, for a frame, past the screen's edges.
                if let node = nodes.first, let plainNodeY {
                    LiftedCard(
                        node: node,
                        plainNodeY: plainNodeY,
                        lifted: isRaised ? 1 : 0,
                        strokes: strokes,
                        top: top,
                        rest: isReleased ? top : nil,
                        holes: holes,
                    )
                }
            }
            .background(alignment: .topLeading) { PlainRowNode(y: $plainNodeY) }
            .onAppear {
                withAnimation(reduceMotion ? nil : RailDrag.lift) { hasRisen = true }
            }
    }
}

/// How far down a plain row its node is, measured from a hidden one-line row at the current text
/// size: what shapes a held card, whichever row it is. The rows' own nodes can't give it in a
/// routine whose only row is the current exercise, its node on its large name well down the row.
private struct PlainRowNode: View {
    @Binding var y: CGFloat?

    var body: some View {
        Text(verbatim: "A")
            .font(.ppRowTitle)
            .railRow()
            // A plain row's place, whatever row the card is.
            .environment(\.railPlace, RailPlace())
            .fixedSize()
            .hidden()
            .backgroundPreferenceValue(RailNodes.self) { nodes in
                GeometryReader { proxy in
                    let measured = nodes.first.map { proxy[$0].y }
                    Color.clear.onChange(of: measured, initial: true) { _, new in
                        if let new {
                            y = new
                        }
                    }
                }
            }
            // Its node is no row's: nothing past here reads it.
            .transformPreference(RailNodes.self) { $0 = [] }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// A held row's card: `CardFill` behind the row, as tall as it, with a soft shadow all around
/// that fades in and out with it. At rest, it is not drawn. Let go, it fades as it settles, but
/// not while it is still a row's height or so from where it settles, `rest`: sent back from under
/// a bar, it crosses rows on its way, and a card already faded would show their text through its
/// own. Over the fill, and over the shadow as far as it reaches, it draws the rail's strokes, so
/// the line and the loops keep one shade through the card and past its edges.
struct LiftedCard: View, Animatable {
    let node: Anchor<CGPoint>
    /// How far down a plain row its node is, which shapes the card.
    let plainNodeY: CGFloat
    /// How far risen it is, from 0 at rest to 1 held.
    var lifted: Double
    var strokes: HeldRailDrawing?
    /// The card's top in the rail's space. The drawing is moved up by it rather than drawn from
    /// moved nodes, so the finger moving the card leaves the drawing's own animation running.
    var top: CGFloat = 0
    /// Where the card's top settles, once let go.
    var rest: CGFloat?
    /// Where the rail shows no strokes, in the rail's space.
    var holes: [CGRect] = []

    var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(lifted, top) }
        set { (lifted, top) = (newValue.first, newValue.second) }
    }

    var body: some View {
        let away = rest.map { min(abs(top - $0) / RailDrag.settleReach, 1) } ?? 0
        GeometryReader { proxy in
            let at = proxy[node]
            CardFill(nodeX: at.x, plainNodeY: plainNodeY, size: proxy.size)
                .shadow(color: .pp(.shadow), radius: RailDrag.liftedShadow)
                .opacity(max(lifted, away))
            // Not faded with the card: they are the rail's own strokes, so they look the same at
            // any lift, where faded, the fill and the shadow fading under them would shade them.
            // Drawn once, over the fill uncut, since the rail's cutouts don't reach a card held
            // over them, and over the shadow as the rail under it draws them.
            strokes?
                .offset(y: -top)
                .mask {
                    ZStack(alignment: .topLeading) {
                        CardFill(nodeX: at.x, plainNodeY: plainNodeY, size: proxy.size)
                        CardShadowReach(
                            card: CardOutline(nodeX: at.x, plainNodeY: plainNodeY),
                            // The shadow fades out within about 1.8 times its radius, measured.
                            reach: 3 * RailDrag.liftedShadow,
                        )
                        .fill(style: FillStyle(eoFill: true))
                        .mask {
                            RailCutouts(holes: holes.map { $0.offsetBy(dx: 0, dy: -top) })
                                .fill(style: FillStyle(eoFill: true))
                        }
                    }
                }
        }
    }
}

/// The raised fill of a held row's card, with no shadow or border, behind a row or a stretch of
/// rows, `size` big, whose first node is `nodeX` from its leading edge. It is shaped as a plain
/// row's card, whose node is `plainNodeY` down it, whichever row it is, never from how far down its
/// own row the node is: on a plain row the node sits as far in from the fill's leading edge as from
/// its top, and the corners are close to concentric with the node, their radius that inset plus
/// half the node, which is `plainNodeY`. It is centered across `size`, so on a screen whose rows
/// are, its edges are as far from the screen's, and a row's content stops that inset short of its
/// trailing edge.
struct CardFill: View {
    let nodeX: CGFloat
    let plainNodeY: CGFloat
    let size: CGSize

    var body: some View {
        let leading = nodeX - plainNodeY
        // Continuous, like the app's other shapes, at the cost of sitting about a point off true
        // concentric with the node.
        RoundedRectangle(cornerRadius: plainNodeY, style: .continuous)
            .fill(.pp(.surfaceRaised))
            .frame(width: max(size.width - 2 * leading, 0), height: size.height)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .offset(x: leading)
    }
}

/// `CardFill`'s shape in its frame, to within the pixel its layout rounds to.
nonisolated struct CardOutline: Shape {
    let nodeX: CGFloat
    let plainNodeY: CGFloat

    func path(in rect: CGRect) -> Path {
        let leading = nodeX - plainNodeY
        let fill = CGRect(
            x: rect.minX + leading,
            y: rect.minY,
            width: max(rect.width - 2 * leading, 0),
            height: rect.height,
        )
        return RoundedRectangle(cornerRadius: plainNodeY, style: .continuous)
            .path(in: fill)
    }
}

/// Around a card, as far as its shadow `reach`es, the card's own shape left out (filled even-odd),
/// less a point all around: what is drawn in it overlaps what the card draws by that point, so
/// the pixels along the card's edge, which each covers in part, are covered whole.
nonisolated struct CardShadowReach: Shape {
    let card: CardOutline
    let reach: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -reach, dy: -reach))
        path.addPath(card.path(in: rect.insetBy(dx: 1, dy: 1)))
        return path
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

/// Where each row's node is from the row's top leading corner, by the row's id.
struct RowNodeInsets: PreferenceKey {
    static let defaultValue: [AnyHashable: CGPoint] = [:]

    static func reduce(
        value: inout [AnyHashable: CGPoint],
        nextValue: () -> [AnyHashable: CGPoint],
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

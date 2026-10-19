import SwiftUI

// A superset's well: the area its rows sit in, sunk into the screen, flat, with no shadow. It
// shows only while a row or a node is held, for the superset the hold changes, where the thumb
// covers the loop: the rail draws it under its strokes (`Rail.drawnWells`, `Rail.spanField`). At
// rest a superset shows its loop alone.

/// How far in from its first row's top and its last row's bottom a well is drawn, so two
/// supersets next to each other read as two wells.
nonisolated let wellEndGap = Spacing.xxs

/// How far out from the rail's own edges a well may reach, into the screen's margin, which is
/// `Spacing.md` on every screen with a rail, keeping a little of it clear.
private nonisolated let wellReach = Spacing.md - Spacing.xs

nonisolated extension RailDrag {
    /// Where a row's node sits, which places the wells: the same on every row, so the furthest
    /// across of `insets`, each row's node in its row, a row swiped open having slid its node to
    /// the left, and the highest. Read at rest; while a row or node is held it stays `known`, as
    /// a moving row reports its node up to a row's height out, and is read only while unknown,
    /// as at a snapshot's moment.
    static func railNode(
        _ insets: some Collection<CGPoint>,
        isHeld: Bool,
        known: CGPoint?,
    ) -> CGPoint? {
        guard !isHeld || known == nil, let x = insets.map(\.x).max(), let y = insets.map(\.y).min()
        else { return known }
        return CGPoint(x: x, y: y)
    }
}

/// The held card's ends where they are its well's: its top when it leads the superset, its
/// bottom when it ends it.
nonisolated struct WellCard {
    var top: CGFloat?
    var bottom: CGFloat?
}

/// A well's outline: its body from `top` to `bottom`, `leading` in from either side of its frame,
/// out past them where that is negative, and its corners.
nonisolated struct WellOutline: Equatable {
    var leading: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    /// The well of the rows from `rows.lowerBound` to `rows.upperBound`, whose nodes are `node.x`
    /// across and `node.y` below each row's top. Its top corners are concentric with the curve at
    /// the top of the loop, which turns into the first row's node: the body's top as far above
    /// the node as its sides are out from the loop's line, `wellEndGap` below the row's top at
    /// most. Its bottom is `wellEndGap` above the last row's bottom, its corners as round as the
    /// top's.
    ///
    /// Where the held card is an end, `card`, that end is concentric with the card's corners
    /// instead (`CardFill`: centered on its node, as round as the node is far down the card), as
    /// far past the card as the sides are out from it. The sides keep the loop's rule either
    /// way, so the well stays centered on the rows, and the card, as wide as the rows less its
    /// node's inset either side, sits inside it.
    init(rows: ClosedRange<CGFloat>, node: CGPoint, pen: LoopPen, card: WellCard = WellCard()) {
        let loop = pen.runX(nodeX: node.x)
        let margin = min(node.y - wellEndGap, loop + wellReach)
        leading = loop - margin
        topRadius = pen.radius + margin
        bottomRadius = topRadius
        top = rows.lowerBound + node.y - margin
        bottom = rows.upperBound - wellEndGap
        let clear = node.x - node.y - leading
        let cardRadius = node.y + clear
        if let cardTop = card.top {
            top = cardTop - clear
            topRadius = cardRadius
        }
        if let cardBottom = card.bottom {
            bottom = cardBottom + clear
            bottomRadius = cardRadius
        }
    }
}

/// A well, or a stretch of one, as `outline` draws it: a continuous rounded rectangle. Its ends
/// and their corners animate, so a well grows and shrinks as rows join and leave, and as a held
/// card comes to an end of it, or settles.
nonisolated struct WellShape: Shape {
    var outline: WellOutline

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>,
    > {
        get {
            AnimatablePair(
                AnimatablePair(outline.top, outline.bottom),
                AnimatablePair(outline.topRadius, outline.bottomRadius),
            )
        }
        set {
            (outline.top, outline.bottom) = (newValue.first.first, newValue.first.second)
            (outline.topRadius, outline.bottomRadius) =
                (newValue.second.first, newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX + outline.leading,
            y: rect.minY + outline.top,
            width: max(rect.width - 2 * outline.leading, 0),
            height: max(outline.bottom - outline.top, 0),
        )
        return UnevenRoundedRectangle(
            topLeadingRadius: outline.topRadius,
            bottomLeadingRadius: outline.bottomRadius,
            bottomTrailingRadius: outline.bottomRadius,
            topTrailingRadius: outline.topRadius,
            style: .continuous,
        ).path(in: body)
    }
}

/// A whole well, as `outline` places it in the rail's space, across a rail `width` wide: a held
/// superset's, or the regroup field's.
struct WellFill: View {
    let outline: WellOutline
    let width: CGFloat
    @ObserveHotReload private var hotReload

    var body: some View {
        WellShape(outline: outline)
            .fill(.pp(.well))
            // From the rail's top, where the outline's ys start, so it lies where they put it.
            .frame(width: width, height: max(outline.bottom, 0), alignment: .topLeading)
            .hotReloadable()
    }
}

/// The well a hold shows, the held row's superset's or a node's field: it fades in as the hold
/// lands, and, `isReleased`, out as the card settles, on the drop's transaction, so it is gone by
/// the time the row draws in its place again. With Reduce Motion it comes and goes at once.
struct HeldWellFill: View {
    let outline: WellOutline
    let width: CGFloat
    let isReleased: Bool
    @State private var isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// `hasRisen` draws it already shown, for a preview or a snapshot of a moment of a drag.
    init(outline: WellOutline, width: CGFloat, isReleased: Bool, hasRisen: Bool) {
        self.outline = outline
        self.width = width
        self.isReleased = isReleased
        _isShown = State(initialValue: hasRisen)
    }

    var body: some View {
        WellFill(outline: outline, width: width)
            .opacity(isShown && !isReleased ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? nil : RailDrag.lift) { isShown = true }
            }
            .hotReloadable()
    }
}

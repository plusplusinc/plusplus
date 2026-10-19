import SwiftUI

// A superset's well: the area its rows sit in, sunk into the screen, flat, with no shadow. At
// rest each row draws its own stretch of it (`RowWell`), so it moves with the rows on whatever
// moves them; while a row or a node is held, the rail draws every well itself, under its strokes
// (`Rail.drawnWells`, `Rail.spanField`), the same shape.

/// How far in from its first row's top and its last row's bottom a well is drawn, so two
/// supersets next to each other read as two wells.
nonisolated let wellEndGap = Spacing.xxs

/// How far out from the rail's own edges a well may reach, into the screen's margin, which is
/// `Spacing.md` on every screen with a rail, keeping a little of it clear.
private nonisolated let wellReach = Spacing.md - Spacing.xs

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
/// superset's, the regroup field's, or one the rail draws while a row or node is held.
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

/// A row's stretch of its superset's well: the well's top on the first row, its bottom on the
/// last, run past the row's edges in between and cut there, so the stretches meet as one well. A
/// row on its own draws none. It hides as the loop does, while a row of the superset is swiped
/// open, and while the rail draws the wells itself, a row or node being held.
struct RowWell: View {
    /// The row's node, from its top leading corner.
    let node: CGPoint
    let size: CGSize
    @ScaledLoopPen private var pen
    @Environment(\.railPlace) private var place
    @ObserveHotReload private var hotReload

    var body: some View {
        let isShown = place.link != .solo && !place.isLoopHidden && !place.isWellHidden
        // Past the row's edges far enough that a corner never shows there.
        let past = size.height + node.y
        var outline = WellOutline(rows: 0 ... size.height, node: node, pen: pen)
        switch place.link {
        case .solo: break
        case .first: outline.bottom = size.height + past
        case .middle: (outline.top, outline.bottom) = (-past, size.height + past)
        case .last: outline.top = -past
        }
        return WellShape(outline: outline)
            .fill(.pp(.well))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // A half point past its bottom, under the next row, which draws after it, so two rows'
            // stretches overlap rather than leave a hairline between them, and none is drawn over
            // the row above's strokes. Out past its sides, where the well reaches.
            .clipShape(Rectangle().path(in: CGRect(
                x: -size.width,
                y: 0,
                width: 3 * size.width,
                height: size.height + 0.5,
            )))
            .opacity(isShown ? 1 : 0)
            // Swiped open, it fades as the loop does; held, the rail's well stands in for it at
            // once.
            .animation(.snappy(duration: 0.2), value: place.isLoopHidden)
            .transaction(value: place.isWellHidden) { $0.animation = nil }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .hotReloadable()
    }
}

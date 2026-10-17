import SwiftUI

/// Where a row sits on its rail: the line starts at the first row's node and ends at the last's.
/// An arriving row holds its place, drawn empty, until it enters. A held row's place is the gap,
/// where only its line draws, and the row draws again over the rail as the card, with no line.
struct RailPlace {
    var isFirst = true
    var isLast = true
    var isArriving = false
    var isGap = false
    /// Whether the row draws its own stretch of line: not on the card, and not while a row is
    /// held, when the rail draws the line once for all of them.
    var drawsOwnLine = true
    /// The card held up off the rail, its node in the color of the text.
    var isRaised = false
    /// Where the row is in a group of rows on the rail, which a loop beside the line marks.
    var link = RailLink.solo
    /// Counts the drops that made the row's group, each flashing its stretch of loop in
    /// `railJoin`.
    var flashes = 0
    /// Whether the row's stretch of loop is hidden: a row of its group is swiped open, which
    /// slides that row's stretch away from the rest.
    var isLoopHidden = false
}

/// Where a row is in a group of rows next to each other on a rail, a superset: on its own, or
/// first, in the middle, or last of its group.
enum RailLink: Equatable {
    case solo
    case first
    case middle
    case last

    /// Each row's link in `ids`, as `joined`, the rows joined to the next, makes them.
    static func links<ID: Hashable>(_ ids: [ID], joined: Set<ID>) -> [ID: Self] {
        var links: [ID: Self] = [:]
        for (index, id) in ids.enumerated() {
            let fromAbove = index > 0 && joined.contains(ids[index - 1])
            let toBelow = index + 1 < ids.count && joined.contains(id)
            links[id] = switch (fromAbove, toBelow) {
            case (false, false): .solo
            case (false, true): .first
            case (true, true): .middle
            case (true, false): .last
            }
        }
        return links
    }
}

extension EnvironmentValues {
    @Entry var railPlace = RailPlace()
}

/// A row's node, centered in the rail column on the row's first line, as the key's icon is: the
/// icon, held invisibly in the column, gives it the key's width and baseline at every text size.
private struct RailNode: View {
    @ScaledMetric(relativeTo: .body) private var size = railNodeSize
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
                        settlingTo: place.isRaised ? .textPrimary : .borderStrong,
                    )
                    .frame(width: size, height: size)
                    .anchorPreference(key: NodeCenter.self, value: .center) { $0 }
                    .anchorPreference(key: RailNodes.self, value: .center) { [$0] }
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
    static let space = "RailRow"
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ScaledMetric(relativeTo: .body) private var nodeSize = railNodeSize
    @State private var nodeLeading: CGFloat = 0
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RailNode()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(Self.space)).midX - nodeSize / 2
                } action: { nodeLeading = $0 }
            content
                .padding(.vertical, Spacing.sm)
                // The lifted card is centered on the row: this ends the content a node inset in.
                .padding(.trailing, max(nodeLeading, 0))
                .frame(minHeight: minHeight, alignment: .top)
                .opacity(place.isArriving ? 0 : 1)
                .offset(y: place.isArriving && !reduceMotion ? -Spacing.xs : 0)
                .entry(
                    RailEntry.content(reduceMotion: reduceMotion),
                    value: place.isArriving,
                )
                .committing(when: place.isArriving)
        }
        .coordinateSpace(.named(Self.space))
        .modifier(SwipeReport())
        // In the gap, the node and content are on the card.
        .opacity(place.isGap ? 0 : 1)
        // The row's stretch of line, top edge to bottom edge through its node, or from the node
        // on the first row and to it on the last, drawn as part of the row so it moves with it.
        // It is drawn in two, above and below the node, so the parts an entry adds can each grow
        // on their own stretch of the shot while the rest stays as it was.
        .backgroundPreferenceValue(NodeCenter.self) { center in
            GeometryReader { proxy in
                // The card has no line: the gap below it has the row's, drawn by the rail while a
                // row is held.
                if let center, place.link != .solo {
                    GroupLoop(
                        node: proxy[center],
                        height: proxy.size.height,
                        link: place.link,
                        flashes: place.flashes,
                    )
                    .opacity(place.isLoopHidden ? 0 : 1)
                    .animation(.snappy(duration: 0.2), value: place.isLoopHidden)
                }
                if let center, place.drawsOwnLine {
                    let node = proxy[center]
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

/// Tells the rail whether the row is swiped open: its swipe slides it sideways, off the rail's
/// leading edge.
private struct SwipeReport: ViewModifier {
    @State private var isSwiped = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { proxy in
                abs(proxy.frame(in: .named(RailDrag.space)).minX) > 0.5
            } action: { isSwiped = $0 }
            .preference(key: RailRowSwiped.self, value: isSwiped)
    }
}

/// Whether a row is swiped open, slid sideways off the rail's leading edge.
struct RailRowSwiped: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// A row's stretch of the loop that marks a group on the rail: a line beside the rail's, on its
/// leading side, a bracket round the group's nodes, read from the bottom back to the top, as a
/// superset goes round. It leaves the first row's node on a curve, runs down past its rows, takes
/// in each middle row's node on a short stroke, and curves into the last row's node. An up
/// chevron just above each later row's node points the way back, a gap in front of its tip and
/// one behind it, so it reads on its own and never as the tip of a curve. The node draws over its
/// strokes. Each change of `flashes` flashes it in `railJoin`, as a new node does, then it settles
/// back to the rail's group gray.
private struct GroupLoop: View {
    let node: CGPoint
    let height: CGFloat
    let link: RailLink
    let flashes: Int
    @ScaledMetric(relativeTo: .body) private var offset: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @ObserveHotReload private var hotReload

    var body: some View {
        let (rest, joined) = (Color.pp(.railGroup), Color.pp(.railJoin))
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        KeyframeAnimator(initialValue: 0.0, trigger: flashes) { joining in
            path.stroke(rest.mix(with: joined, by: joining), style: style)
        } keyframes: { _ in
            RailEntry.joining(after: 0)
        }
        .hotReloadable()
    }

    private var path: Path {
        // The chevron: half its width and its height. The gap in front of its tip, and the one
        // between it and the curve or stroke into the node.
        let (half, rise) = (2.5 * scale, 4.5 * scale)
        let (front, behind) = (3.5 * scale, 5 * scale)
        let radius = 6 * scale
        // Never so far out that the chevron leaves the row.
        let x = max(node.x - offset, half + lineWidth)
        // The chevron's tip, above a later row's node. Every row's node sits as far below its top,
        // on the first line, so where the node is near the top, at the largest text sizes, the
        // chevron reaches up into the row above, and the row above, knowing where, ends its
        // stretch short of the gap in front of the tip.
        let tip = node.y - radius - behind - rise
        let bottom = height + min(tip - front, 0)
        return Path { path in
            switch link {
            case .solo:
                return
            case .first:
                path.move(to: node)
                path.addQuadCurve(
                    to: CGPoint(x: x, y: node.y + radius),
                    control: CGPoint(x: x, y: node.y),
                )
                path.addLine(to: CGPoint(x: x, y: bottom))
            case .middle, .last:
                // On from the row above's stretch, which runs to the row's top, where the gap
                // in front of the tip leaves room.
                if tip - front > 1 {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: tip - front))
                }
                path.move(to: CGPoint(x: x - half, y: tip + rise))
                path.addLine(to: CGPoint(x: x, y: tip))
                path.addLine(to: CGPoint(x: x + half, y: tip + rise))
                path.move(to: CGPoint(x: x, y: tip))
                if link == .middle {
                    path.addLine(to: CGPoint(x: x, y: bottom))
                    path.move(to: CGPoint(x: x, y: node.y))
                    path.addLine(to: node)
                } else {
                    path.addLine(to: CGPoint(x: x, y: node.y - radius))
                    path.addQuadCurve(to: node, control: CGPoint(x: x, y: node.y))
                }
            }
        }
    }
}

/// The rail column's width at the default text size.
private let railColumnWidth: CGFloat = 44

/// The line's width at the default text size: one value, so a new node pops from the line's tip.
let railLineWidth: CGFloat = 2

/// A node's diameter at the default text size.
let railNodeSize: CGFloat = 10

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

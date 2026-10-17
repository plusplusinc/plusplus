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
    /// Whether the row's stretch of loop draws in `railJoin`: the group it marks is joining.
    var isJoining = false
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
                        joining: place.isJoining ? 1 : 0,
                    )
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

/// A row's stretch of the loop that marks a group on the rail: a line beside the rail's, on its
/// leading side, that leaves the first row's node, runs down past its rows, and returns into the
/// last row's node, read from the bottom back to the top, as a superset goes round. An up chevron
/// at the top of each later row points the way back, its tip just short of the row above's line.
/// The node draws over its curves. `joining` mixes it from the rail's group gray into `railJoin`.
private struct GroupLoop: View, Animatable {
    let node: CGPoint
    let height: CGFloat
    let link: RailLink
    var joining: Double
    @ScaledMetric(relativeTo: .body) private var offset: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var radius: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @ObserveHotReload private var hotReload

    var animatableData: Double {
        get { joining }
        set { joining = newValue }
    }

    var body: some View {
        let (rest, joined) = (Color.pp(.railGroup), Color.pp(.railJoin))
        path
            .stroke(
                rest.mix(with: joined, by: joining),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round),
            )
            .hotReloadable()
    }

    private var path: Path {
        // Never so far out that the stroke leaves the row.
        let x = max(node.x - offset, lineWidth)
        // The row above's line stops this far above its bottom, and the chevron's tip this far
        // below the top, a gap in front of the tip.
        let (end, tip) = (3.5 * scale, 0.5 * scale)
        let (half, rise) = (2.5 * scale, 4.5 * scale)
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
                path.addLine(to: CGPoint(x: x, y: height - end))
            case .middle, .last:
                path.move(to: CGPoint(x: x - half, y: tip + rise))
                path.addLine(to: CGPoint(x: x, y: tip))
                path.addLine(to: CGPoint(x: x + half, y: tip + rise))
                path.move(to: CGPoint(x: x, y: tip))
                if link == .middle {
                    path.addLine(to: CGPoint(x: x, y: height - end))
                } else {
                    path.addLine(to: CGPoint(x: x, y: max(node.y - radius, tip)))
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

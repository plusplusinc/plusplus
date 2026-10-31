import SwiftUI

/// Where a row sits on its rail: the line starts at the first row's node and ends at the last's.
/// An arriving row holds its place, drawn empty, until it enters. A held row's place is the gap,
/// and the row draws again over the rail as the card.
struct RailPlace {
    var isFirst = true
    var isLast = true
    var isArriving = false
    var isGap = false
    /// Whether the row draws its own stretch of line and loop: not while a row or its node is
    /// held, when the rail draws every stroke once (`HeldRailDrawing`, `RailDrawing`).
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
    /// The row a workout is on: its node is larger, green, and pulses.
    var isCurrent = false
    /// A row whose sets are all done in a workout: its node is filled purple.
    var isDone = false
    /// The current row with a set logged that stays on it, until the key is back at the start:
    /// its node rests small and gray (`SetBeat`).
    var isSetHeld = false
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
    @ScaledMetric(relativeTo: .body) private var currentSize = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        let pop = RailEntry.pop(reduceMotion: reduceMotion)
        let landing = RailEntry.popStart(reduceMotion: reduceMotion)
        let size = place.isCurrent ? currentSize : size
        RailNodeColumn()
            .overlay {
                Circle()
                    .joiningRail(
                        when: place.isArriving,
                        settlingTo: place.isCurrent ? .accent
                            : place.isRaised ? .textPrimary : place.isDone ? .done : .rail,
                    )
                    .frame(width: size, height: size)
                    .overlay {
                        if place.isCurrent {
                            Color.clear.currentPulse(in: Circle())
                        }
                    }
                    // A set done that stays on this exercise: the node shrinks and grays as the set
                    // logs, rests so while the key does, and pops back green as the line rolls.
                    .keyframeAnimator(
                        initialValue: SetBeat(held: place.isSetHeld),
                        trigger: place.isSetHeld,
                    ) { node, value in
                        let shown = place.isCurrent && !reduceMotion
                        node
                            .overlay {
                                Circle().fill(.pp(.rail)).opacity(shown ? value.gray : 0)
                            }
                            .scaleEffect(shown ? value.scale : 1)
                    } keyframes: { _ in
                        SetBeat.keyframes(held: place.isSetHeld)
                    }
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

/// The rail column as a row's node holds it: the key's icon, held invisibly, gives it the key's
/// width and baseline at every text size.
struct RailNodeColumn: View {
    @ObserveHotReload private var hotReload

    var body: some View {
        Image(systemName: "plus")
            .font(.ppButton)
            .hidden()
            .railColumn()
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
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ScaledMetric(relativeTo: .body) private var nodeSize = railNodeSize
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        RailRowLayout(nodeSize: nodeSize) {
            RailNode()
            content
                .modifier(RailRowContentFrame())
                .opacity(place.isArriving ? 0 : 1)
                .offset(y: place.isArriving && !reduceMotion ? -Spacing.xs : 0)
                .entry(
                    RailEntry.content(reduceMotion: reduceMotion),
                    value: place.isArriving,
                )
                .committing(when: place.isArriving)
        }
        .modifier(SwipeReport())
        // In the gap, the node and content are on the card.
        .opacity(place.isGap ? 0 : 1)
        // The row's stretch of line, top edge to bottom edge through its node, or from the node
        // on the first row and to it on the last, drawn as part of the row so it moves with it.
        // It is drawn in two, above and below the node, so the parts an entry adds can each grow
        // on their own stretch of the shot while the rest stays as it was.
        .backgroundPreferenceValue(NodeCenter.self) { center in
            GeometryReader { proxy in
                // While a row is held, the rail draws every stroke once, under the rows, and the
                // card draws it again over its fill. The row's own strokes are kept then, only
                // hidden, so a group a drop makes flashes, and so they show again at once, in the
                // frame the rail's drawing goes: added back, they would fade in on the
                // transaction that lets go, and the line would go missing for a moment.
                if let center {
                    let node = proxy[center]
                    Group {
                        GroupLoop(
                            node: node,
                            height: proxy.size.height,
                            link: place.link,
                            flashes: place.flashes,
                        )
                        .opacity(place.isLoopHidden ? 0 : 1)
                        .animation(.snappy(duration: 0.2), value: place.isLoopHidden)
                        spine(node: node, height: proxy.size.height)
                    }
                    // The rail's drawing gives way to them at once, the two drawn alike.
                    .opacity(place.drawsOwnLine ? 1 : 0)
                    .transaction(value: place.drawsOwnLine) { $0.animation = nil }
                }
            }
        }
        .hotReloadable()
    }

    /// The row's stretch of line, above its node and below it.
    @ViewBuilder
    private func spine(node: CGPoint, height: CGFloat) -> some View {
        let top = place.isFirst ? node.y : 0
        let above = place.isArriving ? top : node.y
        let below = place.isLast ? node.y : height
        let split = RailEntry.split(height: height, node: node.y)
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

/// A group's loop, drawn by each of its rows for its own stretch: a line beside the rail on its
/// leading side, from the last row's node back up to the first's, as a superset goes round, in
/// the rail's own gray. It curves out of the last row's node and into the first's on the corner of
/// a continuous rounded rectangle, and runs straight up past the rows between, which it leaves
/// alone. A pointed head halfway between each row's node and the next's shows the way up; the
/// line stops a little short of its tip and picks up again beyond it with a round end, as a dashed
/// line would. The node draws over its strokes. Each change of `flashes` flashes it in
/// `railJoin`, as a new node does, then it settles back to the rail's gray.
private struct GroupLoop: View {
    let node: CGPoint
    let height: CGFloat
    let link: RailLink
    let flashes: Int
    @ScaledLoopPen private var pen
    @ObserveHotReload private var hotReload

    var body: some View {
        let (rest, joined) = (Color.pp(.rail), Color.pp(.railJoin))
        KeyframeAnimator(initialValue: 0.0, trigger: flashes) { joining in
            let color = rest.mix(with: joined, by: joining)
            Canvas { context, _ in
                context.fill(run, with: .color(color))
            }
        } keyframes: { _ in
            RailEntry.groupFlash()
        }
        .hotReloadable()
    }

    /// The row's stretch of loop, the loop's line cut square at the row's edges, so it meets the
    /// next row's stretch with no overlap, and, on every row but the last, the head halfway down
    /// to the next node. Rows stack with no spacing and every row's node sits as far down it, so
    /// the next node is a row's height below this one.
    private var run: Path {
        let far = height + node.x + pen.radius * 4
        let ends: (top: CGFloat, bottom: CGFloat)? = switch link {
        case .solo: nil
        case .first: (node.y, node.y + far)
        case .middle: (-far, height + far)
        case .last: (node.y - far, node.y)
        }
        guard let ends else { return Path() }
        let x = pen.runX(nodeX: node.x)
        let line = pen.line(top: ends.top, bottom: ends.bottom, nodeX: node.x, x: x)
            .intersection(Path(CGRect(x: 0, y: 0, width: node.x, height: height)))
        guard link == .first || link == .middle else { return line }
        // Kept whole inside the row: on a row given space above its label, as the next exercise
        // of a workout is, half its height below the node is at its bottom edge.
        let middle = min(node.y + height / 2, height - pen.length / 2 - pen.gap - pen.lineWidth)
        let head = pen.head(middle: middle, x: x)
        return line.subtracting(head.opening).union(head.added)
    }
}

/// The rail column's width at the default text size.
private let railColumnWidth: CGFloat = 44

/// The line's width at the default text size: one value, so a new node pops from the line's tip.
let railLineWidth: CGFloat = 2

/// A node's diameter at the default text size.
let railNodeSize: CGFloat = 10

/// The current exercise's node's diameter at the default text size.
let currentNodeSize: CGFloat = 14

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

/// The current node's beat as a set logs that stays on its exercise (Dave, 2026-10-30): it
/// shrinks to half and fades to the rail's gray as the set logs, rests so, and pops back full
/// and green, with a bounce, as the progress line rolls.
struct SetBeat {
    var scale: Double
    /// How far the node is covered in the rail's gray.
    var gray: Double

    /// The node at rest, or held small and gray.
    init(held: Bool = false) {
        scale = held ? 0.5 : 1
        gray = held ? 1 : 0
    }

    /// To held, or back from it, from wherever the node is.
    @KeyframesBuilder<Self>
    static func keyframes(held: Bool) -> some Keyframes<Self> {
        let end = Self(held: held)
        KeyframeTrack(\.scale) {
            if held {
                CubicKeyframe(end.scale, duration: 0.2)
            } else {
                // Its own settling time: cut at 0.4 s, it stopped 2 % large.
                SpringKeyframe(end.scale, spring: .bouncy)
            }
        }
        KeyframeTrack(\.gray) {
            CubicKeyframe(end.gray, duration: held ? 0.2 : 0.12)
        }
    }
}

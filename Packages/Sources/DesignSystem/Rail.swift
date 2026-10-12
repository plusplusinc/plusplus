import SwiftUI

/// Rows on a rail, one for each element of `data`: a line runs through the rows' nodes, from
/// the first node to the last, above the view at the rail's end, a key with a `plus` icon in the
/// rail column.
///
/// Rows stack with no spacing. Each is made with `railRow()`, which gives it its node, its
/// height, and its own stretch of the line, so nodes fall at an even rhythm whether a row has
/// one line or two, and anything applied to the row, such as swipe actions, carries its node
/// and its stretch of line with it. At rest the stretches abut and read as one line. A row removed
/// fades out quickly.
///
/// The row named by `arriving` takes its place, and the end view moves down for it, but nothing
/// of it shows and the line still ends at the node above. When `arriving` lets it go, it enters
/// in beats: its content fades in, the line shoots down to where its node sits, the node pops
/// in as the line lands, and the new line and node, drawn in `railJoin`, the color of something
/// joining the rail, settle to the rail's own colors. With Reduce Motion, the line and node
/// appear in those colors with the content.
/// The entry starts `railEntryDelay` after the transaction that lets it go; a row let go in any
/// other transaction, or added with no `arriving`, takes that transaction's animation.
public struct Rail<Data: RandomAccessCollection, Row: View, End: View>: View
    where Data.Element: Identifiable
{
    private let data: Data
    private let arriving: Data.Element.ID?
    private let row: (Data.Element) -> Row
    private let end: End

    @ObserveHotReload private var hotReload

    public init(
        _ data: Data,
        arriving: Data.Element.ID? = nil,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.data = data
        self.arriving = arriving
        self.row = row
        self.end = end()
    }

    public var body: some View {
        let first = data.first?.id
        // Until the arriving row enters, the line ends at the node above it.
        let lastOnLine = data.last { $0.id != arriving }?.id
        VStack(alignment: .leading, spacing: 0) {
            // Each row learns its place from the rail. Rows taken as a view's subviews could
            // not: a subview resolves in its container's environment, not one set on it.
            ForEach(data) { item in
                let isArriving = item.id == arriving
                let place = RailPlace(
                    isFirst: item.id == first,
                    isLast: isArriving || item.id == lastOnLine,
                    isArriving: isArriving,
                    isAboveArriving: arriving != nil && !isArriving && item.id == lastOnLine,
                )
                row(item)
                    .environment(\.railPlace, place)
                    // A row's swipe closes when its action runs, so a deleted row slid back to rest
                    // as it went. It fades out first instead, while the rows below close the gap.
                    // An arriving row draws nothing until its entry, so its fade shows nothing.
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.animation(.snappy(duration: 0.15)),
                    ))
            }
            // Between the last row and the end view, as the design has it.
            end.padding(.top, data.isEmpty ? 0 : Spacing.xxs)
        }
        .hotReloadable()
    }
}

extension Animation {
    /// A row going onto or off a rail, and what it moves: quicker than `.snappy`'s default, which
    /// let the rows below a deleted one drift up.
    public static let railChange = Animation.snappy(duration: 0.25)
}

/// Where a row sits on its rail: the line starts at the first row's node and ends at the last's.
/// An arriving row holds its place, drawn empty, until it enters.
struct RailPlace {
    var isFirst = true
    var isLast = true
    var isArriving = false
    /// Whether the row below is arriving, so this row's stretch below its node will join it.
    var isAboveArriving = false
}

extension Transaction {
    /// How long a row's entry waits after the transaction that lets it onto its rail. With none,
    /// the transaction's own animation applies, as it does to a delete.
    @Entry public var railEntryDelay: TimeInterval?
}

/// A row's entry, from when the rail lets it go, as a sequence of beats, each starting `lead`
/// in: the row's name fades in with a small drop; then the line shoots down from the node above
/// to where this row's node sits, easing in so it starts slow and lands fast; then the node pops
/// in, with a small, crisp overshoot, as the line lands; then the new line and node settle from
/// `railJoin` to gray (`JoiningRail`). The first row has no line above it, so its node pops
/// after the name. With Reduce Motion, the line and node appear with the name, without a shot or
/// an overshoot.
private enum Entry {
    static let name: TimeInterval = 0.12
    static let shot: TimeInterval = 0.18
    static let pop: TimeInterval = 0.15

    static func content(after lead: TimeInterval) -> Animation {
        .easeOut(duration: name).delay(lead)
    }

    /// When the node pops, from when the row is let go: on the line's landing.
    static func popStart(isFirst: Bool) -> TimeInterval {
        name + (isFirst ? 0 : shot)
    }

    static func pop(isFirst: Bool, reduceMotion: Bool) -> (_ lead: TimeInterval) -> Animation? {
        let bounce = reduceMotion ? 0 : 0.25
        let start = reduceMotion ? 0 : popStart(isFirst: isFirst)
        return { .snappy(duration: pop, extraBounce: bounce).delay($0 + start) }
    }

    /// One stretch of the shot. The shot runs from the node above to this row's node, a stretch
    /// in each row, on one quadratic ease-in: the row above's stretch takes its slow start, the
    /// share of the time `split` of the way along, and this row's stretch the fast rest. Each
    /// row estimates `split` from its own height and node, as rows share a rhythm.
    static func shot(
        from start: Double,
        to end: Double,
        reduceMotion: Bool,
    ) -> (_ lead: TimeInterval) -> Animation? {
        guard !reduceMotion, end > start else { return { _ in nil } }
        // The arc of y = x² from x = start to x = end, rescaled to a unit square, is a quadratic
        // Bézier with its control point halfway along, at the start's tangent; as a cubic:
        let rise = start / (start + end)
        let curve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 1 / 3, y: rise * 2 / 3),
            endControlPoint: UnitPoint(x: 2 / 3, y: (1 + rise * 2) / 3),
        )
        let duration = shot * (end - start)
        return { .timingCurve(curve, duration: duration).delay($0 + name + shot * start) }
    }

    /// How far along the shot, in time, it crosses from the row above into this one: the row
    /// above's stretch below its node, against the whole span from node to node.
    static func split(height: CGFloat, node: CGFloat) -> Double {
        guard height > 0 else { return 0.5 }
        return Double((height - node) / height).squareRoot()
    }
}

extension View {
    /// Animates changes to `value` with `animation`, given the transaction's entry delay.
    fileprivate func entry(
        _ animation: @escaping (TimeInterval) -> Animation?,
        value: some Equatable,
    ) -> some View {
        transaction(value: value) { transaction in
            if let lead = transaction.railEntryDelay {
                transaction.animation = animation(lead)
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var railPlace = RailPlace()
}

/// A row's node, centered in the rail column on the row's first line, as the key's icon is: the
/// icon, held invisibly in the column, gives it the key's width and baseline at every text size.
private struct RailNode: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        let pop = Entry.pop(isFirst: place.isFirst, reduceMotion: reduceMotion)
        Image(systemName: "plus")
            .font(.ppButton)
            .hidden()
            .railColumn()
            .overlay {
                Circle()
                    .joiningRail(
                        when: place.isArriving,
                        settlingTo: .borderStrong,
                        after: Entry.popStart(isFirst: place.isFirst) + Entry.pop,
                    )
                    .frame(width: size, height: size)
                    .anchorPreference(key: NodeCenter.self, value: .center) { $0 }
                    .scaleEffect(place.isArriving ? 0 : 1)
                    .entry(pop, value: place.isArriving)
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
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var lineWidth: CGFloat = 2
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RailNode()
            content
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: minHeight, alignment: .top)
                .opacity(place.isArriving ? 0 : 1)
                .offset(y: place.isArriving && !reduceMotion ? -Spacing.xs : 0)
                .entry(Entry.content, value: place.isArriving)
        }
        // The row's stretch of line, top edge to bottom edge through its node, or from the node
        // on the first row and to it on the last, drawn as part of the row so it moves with it.
        // It is drawn in two, above and below the node, so the part an entry adds can draw in
        // `railJoin` while the rest stays as it was.
        .backgroundPreferenceValue(NodeCenter.self) { center in
            GeometryReader { proxy in
                if let center {
                    let node = proxy[center]
                    let top = place.isFirst ? node.y : 0
                    let above = place.isArriving ? top : node.y
                    let below = place.isLast ? node.y : proxy.size.height
                    let split = Entry.split(height: proxy.size.height, node: node.y)
                    let settle = Entry.popStart(isFirst: false) + Entry.pop
                    Rectangle()
                        .joiningRail(when: place.isArriving, settlingTo: .rail, after: settle)
                        .frame(width: lineWidth, height: above - top)
                        .position(x: node.x, y: (top + above) / 2)
                        .entry(
                            Entry.shot(from: split, to: 1, reduceMotion: reduceMotion),
                            value: place.isArriving,
                        )
                    Rectangle()
                        .joiningRail(when: place.isAboveArriving, settlingTo: .rail, after: settle)
                        .frame(width: lineWidth, height: below - node.y)
                        .position(x: node.x, y: (node.y + below) / 2)
                        .entry(
                            Entry.shot(from: 0, to: split, reduceMotion: reduceMotion),
                            value: place.isLast,
                        )
                }
            }
        }
        .hotReloadable()
    }
}

/// A part of the rail an entry adds: when `trigger` changes, it shows in `railJoin`, the color
/// of something joining the rail, until the node has popped, `settleStart` after the row is let
/// go, give or take the lead-in, then settles to `rest`. A keyframe timeline, not an animation:
/// a shape takes its color and its ends from one transaction, and its ends move on the entry's
/// quicker ones. With Reduce Motion, it is `rest` throughout.
private struct JoiningRail: ViewModifier {
    let trigger: Bool
    let rest: ColorToken
    let settleStart: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        // The tokens resolve here, on the main actor; the animator's frames only mix the two.
        let (rest, joined) = (Color.pp(rest), Color.pp(.railJoin))
        Group {
            if reduceMotion {
                content.foregroundStyle(rest)
            } else {
                content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, joining in
                    view.foregroundStyle(rest.mix(with: joined, by: joining))
                } keyframes: { _ in
                    MoveKeyframe(1)
                    // The keyframes start as the row is let go, before its lead-in, which is
                    // at most a sheet's 0.15 s.
                    LinearKeyframe(1, duration: settleStart + 0.15)
                    CubicKeyframe(0, duration: 0.3)
                }
            }
        }
        .hotReloadable()
    }
}

extension View {
    fileprivate func joiningRail(
        when trigger: Bool,
        settlingTo rest: ColorToken,
        after settleStart: TimeInterval,
    ) -> some View {
        modifier(JoiningRail(trigger: trigger, rest: rest, settleStart: settleStart))
    }
}

/// The rail column's width at the default text size.
private let railColumnWidth: CGFloat = 44

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

#Preview {
    let exercises = [
        PreviewRow(title: "Goblet squat", detail: "Kettlebell"),
        PreviewRow(title: "Push-up", detail: nil),
        PreviewRow(title: "Farmer\u{2019}s carry", detail: "Dumbbells"),
    ]
    Rail(exercises) { exercise in
        RowLabel(title: exercise.title, detail: exercise.detail).railRow()
    } end: {
        Button("Add exercise", systemImage: "plus") { }
            .buttonStyle(.key)
    }
    .padding()
    .background(Color.pp(.background))
}

private struct PreviewRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
}

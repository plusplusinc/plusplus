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
    private let entryLead: TimeInterval
    private let row: (Data.Element) -> Row
    private let end: End

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    public init(
        _ data: Data,
        arriving: Data.Element.ID? = nil,
        entryLead: TimeInterval = 0,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.data = data
        self.arriving = arriving
        self.entryLead = entryLead
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
                    entryLead: entryLead,
                )
                // An arriving row's place opens with its entry's shot, so the end view is pushed
                // down as far as the line has grown, on every frame.
                OpeningSpace(progress: isArriving ? 0 : 1) {
                    row(item).environment(\.railPlace, place)
                }
                // The last row under the one above, so the pulse the row above draws to it shows
                // over the new row's stretch of line.
                .zIndex(item.id == data.last?.id ? -1 : 0)
                .entry(RailEntry.space(reduceMotion: reduceMotion), value: isArriving)
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
    /// How long an entry waits, once the row is let go, before the row starts to show.
    var entryLead: TimeInterval = 0
}

extension EnvironmentValues {
    @Entry var railPlace = RailPlace()
}

/// A row's node, centered in the rail column on the row's first line, as the key's icon is: the
/// icon, held invisibly in the column, gives it the key's width and baseline at every text size.
private struct RailNode: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var lineWidth: CGFloat = 2
    @Environment(\.railPlace) private var place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        let pop = RailEntry.pop(isFirst: place.isFirst, reduceMotion: reduceMotion)
        let landing = RailEntry.popStart(isFirst: place.isFirst, reduceMotion: reduceMotion)
        Image(systemName: "plus")
            .font(.ppButton)
            .hidden()
            .railColumn()
            .overlay {
                Circle()
                    .joiningRail(
                        when: place.isArriving,
                        settlingTo: .borderStrong,
                        isFirst: place.isFirst,
                    )
                    .frame(width: size, height: size)
                    .anchorPreference(key: NodeCenter.self, value: .center) { $0 }
                    // It pops from the size of the point that led the line, as the line lands:
                    // shown at that size and grown to its own in the same moment.
                    .scaleEffect(place.isArriving ? lineWidth * RailEntry.pointScale / size : 1)
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
                .entry(
                    RailEntry.content(isFirst: place.isFirst, reduceMotion: reduceMotion),
                    value: place.isArriving,
                )
                .joiningContent(when: place.isArriving)
                .committing(when: place.isArriving)
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
                    // Drawn by the row above the arriving one, over the line and under this
                    // row's node, so it emerges from under the node.
                    if !reduceMotion {
                        leadingPoint(from: node, rowHeight: proxy.size.height)
                    }
                }
            }
        }
        .hotReloadable()
    }
}

extension RailRow {
    /// The blue pulse that leads the line down from this row's node to the arriving row's below
    /// it (`Pulse`), a row's height down, as rows share a rhythm. It shows from the shot's start
    /// and gives way to the arriving row's node as that pops.
    private func leadingPoint(from node: CGPoint, rowHeight: CGFloat) -> some View {
        let landing = RailEntry.popStart(isFirst: false, reduceMotion: false)
        let time = place.isAboveArriving ? 0 : RailEntry.pulseEnd
        return Pulse(
            time: time,
            node: CGPoint(x: node.x, y: node.y + rowHeight),
            gap: rowHeight,
            lineWidth: lineWidth,
            duration: RailEntry.shot,
            end: RailEntry.pulseEnd,
        )
        .fill(.pp(.railJoin))
        .entry(RailEntry.pulse(reduceMotion: false), value: place.isAboveArriving)
        .opacity(place.isAboveArriving ? 1 : 0)
        .entry(RailEntry.step(at: landing), value: place.isAboveArriving)
        .opacity(place.isAboveArriving ? 0 : 1)
        .entry(RailEntry.step(at: RailEntry.start), value: place.isAboveArriving)
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

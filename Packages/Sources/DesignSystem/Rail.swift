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
/// of it shows and the line still ends at the node above. When `arriving` lets it go, it enters:
/// the line grows down to where its node sits, then the node pops in, as its content fades in.
/// The entry starts `railEntryDelay` after the transaction that lets it go.
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
                )
                row(item)
                    .environment(\.railPlace, place)
                    // A row's swipe closes when its action runs, so a deleted row slid back to rest
                    // as it went. It fades out first instead, while the rows below close the gap.
                    // A row comes in through its entry, drawn by `railRow()`.
                    .transition(.asymmetric(
                        insertion: .identity,
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
}

extension Transaction {
    /// How long a row's entry waits after the transaction that lets it onto its rail.
    @Entry public var railEntryDelay: TimeInterval = 0
}

/// A row's entry, from when the rail lets it go: the line grows down, a stretch in the row above
/// and then one in this row, the node pops in, with a small, crisp overshoot, as the line
/// arrives, and the content fades in alongside. About a third of a second end to end. The first
/// row has no line above it, so its node pops at once. Each starts `lead` in.
private enum Entry {
    /// The row above's stretch, from its node to its bottom edge.
    static func lineAbove(after lead: TimeInterval) -> Animation {
        .easeIn(duration: 0.1).delay(lead)
    }

    /// This row's stretch, from its top edge to its node, picking up where the one above ends.
    static func line(after lead: TimeInterval) -> Animation {
        .easeOut(duration: 0.06).delay(lead + 0.1)
    }

    /// The node's pop, as the line arrives, or at once on the first row.
    static func pop(isFirst: Bool) -> (_ lead: TimeInterval) -> Animation {
        { .snappy(duration: 0.2, extraBounce: 0.25).delay($0 + (isFirst ? 0 : 0.14)) }
    }

    static func content(after lead: TimeInterval) -> Animation {
        .easeOut(duration: 0.2).delay(lead + 0.08)
    }
}

extension View {
    /// Animates changes to `value` with `animation`, given the transaction's entry delay.
    fileprivate func entry(
        _ animation: @escaping (TimeInterval) -> Animation,
        value: some Equatable,
    ) -> some View {
        transaction(value: value) { $0.animation = animation($0.railEntryDelay) }
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
    @ObserveHotReload private var hotReload

    var body: some View {
        Image(systemName: "plus")
            .font(.ppButton)
            .hidden()
            .railColumn()
            .overlay {
                Circle()
                    .fill(.pp(.borderStrong))
                    .frame(width: size, height: size)
                    .anchorPreference(key: NodeCenter.self, value: .center) { $0 }
                    .scaleEffect(place.isArriving ? 0 : 1)
                    .entry(Entry.pop(isFirst: place.isFirst), value: place.isArriving)
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
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RailNode()
            content
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: minHeight, alignment: .top)
                .opacity(place.isArriving ? 0 : 1)
                .entry(Entry.content, value: place.isArriving)
        }
        // The row's stretch of line, top edge to bottom edge through its node, or from the node
        // on the first row and to it on the last, drawn as part of the row so it moves with it.
        .backgroundPreferenceValue(NodeCenter.self) { center in
            GeometryReader { proxy in
                if let center {
                    let node = proxy[center]
                    let top = place.isFirst ? node.y : 0
                    let end = place.isLast ? node.y : proxy.size.height
                    let bottom = place.isArriving ? top : end
                    Rectangle()
                        .fill(.pp(.rail))
                        .frame(width: lineWidth, height: bottom - top)
                        .position(x: node.x, y: (top + bottom) / 2)
                        .entry(Entry.lineAbove, value: place.isLast)
                        .entry(Entry.line, value: place.isArriving)
                }
            }
        }
        .hotReloadable()
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

import SwiftUI

/// Rows on a rail, one for each element of `data`: a line runs through the rows' nodes, from
/// the first node to the last, above the view at the rail's end, a key with a `plus` icon in the
/// rail column.
///
/// Rows stack with no spacing. Each is made with `railRow()`, which gives it its node, its
/// height, and its own stretch of the line, so nodes fall at an even rhythm whether a row has
/// one line or two, and anything applied to the row, such as swipe actions, carries its node
/// and its stretch of line with it. At rest the stretches abut and read as one line.
public struct Rail<Data: RandomAccessCollection, Row: View, End: View>: View
where Data.Element: Identifiable {
    private let data: Data
    private let row: (Data.Element) -> Row
    private let end: End

    @ObserveHotReload private var hotReload

    public init(
        _ data: Data,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder end: () -> End,
    ) {
        self.data = data
        self.row = row
        self.end = end()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Each row learns its place from the rail. Rows taken as a view's subviews could
                // not: a subview resolves in its container's environment, not one set on it.
                ForEach(data) { item in
                    row(item).environment(
                        \.railPlace,
                        RailPlace(isFirst: item.id == data.first?.id, isLast: item.id == data.last?.id),
                    )
                }
            }
            // Between the last row and the end view, as the design has it.
            .padding(.bottom, data.isEmpty ? 0 : Spacing.xxs)
            end
        }
        .hotReloadable()
    }
}

/// Where a row sits on its rail: the line starts at the first row's node and ends at the last's.
struct RailPlace {
    var isFirst = true
    var isLast = true
}

extension EnvironmentValues {
    @Entry var railPlace = RailPlace()
}

/// The rail column, empty: a key's icon held invisibly in it gives the column the key's width,
/// and a row's first baseline, at every text size.
private struct RailColumn: View {
    @ObserveHotReload private var hotReload

    var body: some View {
        Image(systemName: "plus")
            .font(.ppButton)
            .hidden()
            .railColumn()
            .hotReloadable()
    }
}

/// A row's node, centered in the rail column on the row's first line, as the key's icon is.
private struct RailNode: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10
    @ObserveHotReload private var hotReload

    var body: some View {
        RailColumn()
            .overlay {
                Circle()
                    .fill(.pp(.borderStrong))
                    .frame(width: size, height: size)
                    .anchorPreference(key: NodeCenter.self, value: .center) { $0 }
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
        }
        // The row's stretch of line, top edge to bottom edge through its node, or from the node
        // on the first row and to it on the last, drawn as part of the row so it moves with it.
        .backgroundPreferenceValue(NodeCenter.self) { center in
            GeometryReader { proxy in
                if let center {
                    let node = proxy[center]
                    let top = place.isFirst ? node.y : 0
                    let bottom = place.isLast ? node.y : proxy.size.height
                    Rectangle()
                        .fill(.pp(.rail))
                        .frame(width: lineWidth, height: bottom - top)
                        .position(x: node.x, y: (top + bottom) / 2)
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

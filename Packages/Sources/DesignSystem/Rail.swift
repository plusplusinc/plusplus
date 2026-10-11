import SwiftUI

/// Rows on a rail: a line runs from the first row's node down to the view at the rail's end, a
/// key with a `plus` icon in the rail column.
///
/// Rows stack with no spacing. Each is made with `railRow()`, which gives it its node and its
/// height, so nodes fall at an even rhythm whether a row has one line or two, and anything
/// applied to the row, such as swipe actions, carries its node with it.
public struct Rail<Rows: View, End: View>: View {
    private let rows: Rows
    private let end: End

    @ScaledMetric(relativeTo: .body) private var lineWidth: CGFloat = 2
    /// Between the last row and the end view, as the design has it.
    @ScaledMetric(relativeTo: .body) private var endGap: CGFloat = 2
    @ObserveHotReload private var hotReload

    public init(@ViewBuilder rows: () -> Rows, @ViewBuilder end: () -> End) {
        self.rows = rows()
        self.end = end()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: rows) { rows in
                VStack(alignment: .leading, spacing: 0) {
                    rows
                }
                .padding(.bottom, rows.isEmpty ? 0 : endGap)
                .backgroundPreferenceValue(FirstNode.self) { first in
                    GeometryReader { proxy in
                        if let first {
                            let center = proxy[first]
                            let height = max(0, proxy.size.height - center.y)
                            Rectangle()
                                .fill(.pp(.rail))
                                .frame(width: lineWidth, height: height)
                                .offset(x: center.x - lineWidth / 2, y: center.y)
                        }
                    }
                }
            }
            end
        }
        .hotReloadable()
    }
}

/// A row's node: a key's icon held invisibly in the rail column gives the column the key's width
/// and the row's first baseline at every text size; the node is centered on it, as the key's
/// icon is.
private struct RailNode: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10
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
                    .anchorPreference(key: FirstNode.self, value: .center) { $0 }
            }
            .accessibilityHidden(true)
            .hotReloadable()
    }
}

/// Where the first node's center is; the line starts there.
private struct FirstNode: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

private struct RailRow: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var inset: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RailNode()
            content
                .padding(.vertical, inset)
                .frame(minHeight: minHeight, alignment: .top)
        }
        // One element, so VoiceOver reads the row and offers its actions in one place.
        .accessibilityElement(children: .combine)
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
    Rail {
        RowLabel(title: "Goblet squat", detail: "Kettlebell").railRow()
        RowLabel(title: "Push-up", detail: nil).railRow()
    } end: {
        Button("Add exercise", systemImage: "plus") { }
            .buttonStyle(.key)
    }
    .padding()
    .background(Color.pp(.background))
}

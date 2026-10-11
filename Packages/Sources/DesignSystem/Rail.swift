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
                // Between the last row and the end view, as the design has it.
                .padding(.bottom, rows.isEmpty ? 0 : Spacing.xxs)
                // The line has a rail column of its own and takes only its top from the first
                // node, so a row swiped aside, node and all, leaves the line where it is.
                .backgroundPreferenceValue(FirstNode.self) { first in
                    GeometryReader { proxy in
                        if let first {
                            RailColumn()
                                .frame(maxHeight: .infinity)
                                .overlay {
                                    Rectangle().fill(.pp(.rail)).frame(width: lineWidth)
                                }
                                .padding(.top, proxy[first].y)
                        }
                    }
                }
            }
            end
        }
        .hotReloadable()
    }
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
                    .anchorPreference(key: FirstNode.self, value: .center) { $0 }
            }
            .accessibilityHidden(true)
            .hotReloadable()
    }
}

/// Where the first node's center is; the line starts at its height.
private struct FirstNode: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

private struct RailRow: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RailNode()
            content
                .padding(.vertical, Spacing.sm)
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

#if os(iOS)
import SwiftUI

/// Create's row label: a green + and its title, and under the title, while it carries
/// anything, what the thing it makes will start with, as an exercise row's equipment line
/// reads. Add exercise's Create row and the Workouts list's Create workout row both draw it,
/// one in a list and one out of a list, so it lays the + out itself rather than through a
/// list's label: the + large in a column of its own, centered on the lines. At the
/// accessibility sizes the title wraps beside the +, set on its first line: a list's label
/// there ran its second line back under the +, past its own frame.
public struct CreateLabel: View {
    let title: String
    let detail: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The +'s column: as wide as a list gave its label's icon on the iOS 27 simulator, so Add
    /// exercise's row kept its place to within a point when it stopped drawing a `Label`.
    @ScaledMetric(relativeTo: .body) private var iconWidth = 23.0

    public init(title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                    lines
                }
            } else {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "plus")
                        .imageScale(.large)
                        .frame(width: iconWidth)
                        .accessibilityHidden(true)
                    lines
                }
            }
        }
        .font(.ppRowTitle)
        .makesSomething()
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.ppRowDetail)
                    .foregroundStyle(Color.pp(.textSecondary))
            }
        }
    }
}

extension View {
    /// The room a plain `List` gives a row, for one drawn outside a list, as the Workouts list's
    /// Create workout row is, so it stands as tall as Add exercise's Create row: the full width,
    /// a list row's insets, and the list's least row height, read from the environment.
    public func listRowRoom() -> some View {
        modifier(ListRowRoom())
    }
}

private struct ListRowRoom: ViewModifier {
    /// A plain list row's room above and below its content on iOS 27, the same at every text
    /// size. SwiftUI gives no way to read it, so `ListRowRoomTests` holds this to a real list's.
    static let verticalInset: CGFloat = 15
    @Environment(\.defaultMinListRowHeight) private var minHeight

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Self.verticalInset)
            .frame(minHeight: minHeight)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        CreateLabel(title: "Create workout", detail: "Legs, Dumbbells").listRowRoom()
        CreateLabel(title: "Create workout", detail: nil).listRowRoom()
    }
    .padding(.vertical)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.pp(.background))
}
#endif

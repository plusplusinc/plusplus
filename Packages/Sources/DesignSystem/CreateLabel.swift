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

#Preview {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        CreateLabel(title: "Create workout", detail: "Legs, Dumbbells")
        CreateLabel(title: "Create workout", detail: nil)
    }
    .font(.ppRowTitle)
    .makesSomething()
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.pp(.background))
}
#endif

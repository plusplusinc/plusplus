import SwiftUI

/// A row's name over an optional detail line. With no detail there is no line at all, not an
/// empty one. VoiceOver reads it as one element, "name, detail".
public struct RowLabel: View {
    private let title: String
    private let detail: String?

    /// Between the name and the detail line, as the design has it.
    @ScaledMetric(relativeTo: .subheadline) private var lineGap: CGFloat = 2
    @ObserveHotReload private var hotReload

    public init(title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: lineGap) {
            Text(title)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
            if let detail {
                Text(detail)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .hotReloadable()
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        RowLabel(title: "Goblet squat", detail: "Kettlebell")
        RowLabel(title: "Dumbbell bench press", detail: "Dumbbells, bench")
        RowLabel(title: "Push-up", detail: nil)
    }
    .padding()
    .background(Color.pp(.background))
}

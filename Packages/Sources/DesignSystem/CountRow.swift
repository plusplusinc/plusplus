import SwiftUI

/// A row that counts what was done: a title at the leading edge, its count at the trailing edge
/// in purple with SF Mono numbers, and under them a bar the row's width whose purple fill is
/// `fraction` of it, on a `toDo` track. A stressed row's title reads in primary text at the row
/// title's weight, the others' in secondary text. VoiceOver reads the row as one element,
/// `spoken`. At the accessibility sizes the count moves under the title. It has no room of its
/// own above or below: a list of them spaces them, with no line between, as the bars part them.
public struct CountRow: View {
    private let title: String
    private let count: String
    private let fraction: Double
    private let isStressed: Bool
    private let spoken: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        _ title: String,
        count: String,
        fraction: Double,
        isStressed: Bool,
        spoken: String,
    ) {
        self.title = title
        self.count = count
        self.fraction = fraction
        self.isStressed = isStressed
        self.spoken = spoken
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            titleAndCount
            FillBar(fraction: fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var titleAndCount: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
        return layout {
            Text(title)
                .font(isStressed ? .ppRowTitle : .ppWorkoutName)
                .foregroundStyle(.pp(isStressed ? .textPrimary : .textSecondary))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(AttributedString.monoNumbers(count, font: .ppRowDetailNumber))
                .font(.ppRowDetail)
                .foregroundStyle(.pp(.done))
                .fixedSize()
        }
    }
}

/// A thin bar across its width: `fraction` of it, from the leading edge, filled `done` purple,
/// on a `toDo` track; an empty track at 0. Sized with the detail line's text.
public struct FillBar: View {
    private let fraction: Double

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 4

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public var body: some View {
        Capsule()
            .fill(.pp(.toDo))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.pp(.done))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                        .opacity(fraction > 0 ? 1 : 0)
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        CountRow("Core", count: "0", fraction: 0, isStressed: true, spoken: "Core")
        CountRow("Arms", count: "4", fraction: 0.25, isStressed: true, spoken: "Arms")
        CountRow("Legs", count: "16", fraction: 1, isStressed: false, spoken: "Legs")
    }
    .padding(.horizontal, Spacing.md)
    .background(Color.pp(.background))
}

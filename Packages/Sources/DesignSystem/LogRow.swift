import SwiftUI

/// What a Log row says after its title: a gain in green, or a quiet word in gray ("Same",
/// "First time", a drop, "16 days ago", "3 workouts").
public enum LogTag: Equatable, Sendable {
    case gain(String)
    case quiet(String)
}

/// A row of Log: a title, an optional tag at its trailing end, an optional line of logged
/// figures in purple with SF Mono numbers, and an optional gray detail line. VoiceOver reads the
/// row as one element, `spoken`. At the accessibility sizes the tag moves under the title.
public struct LogRow: View {
    private let title: String
    private let tag: LogTag?
    private let figures: String?
    private let detail: String?
    private let spoken: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        _ title: String,
        tag: LogTag? = nil,
        figures: String? = nil,
        detail: String? = nil,
        spoken: String,
    ) {
        self.title = title
        self.tag = tag
        self.figures = figures
        self.detail = detail
        self.spoken = spoken
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            titleAndTag
            if let figures {
                Text(AttributedString.monoNumbers(figures, font: .ppRowDetailNumber))
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.done))
            }
            if let detail {
                Text(AttributedString.monoNumbers(detail, font: .ppRowDetailNumber))
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.md)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var titleAndTag: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
        return layout {
            Text(title)
                .font(.ppWorkoutName)
                .foregroundStyle(.pp(.textPrimary))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            tag.map(tagText)
        }
    }

    private func tagText(_ tag: LogTag) -> some View {
        let isGain = if case .gain = tag {
            true
        } else {
            false
        }
        let text = switch tag {
        case let .gain(text), let .quiet(text): text
        }
        let weight: Font.Weight = isGain ? .semibold : .regular
        let color: ColorToken = isGain ? .accent : .textSecondary
        return Text(AttributedString.monoNumbers(text, font: .ppRowDetailNumber.weight(weight)))
            .font(.ppRowDetail.weight(weight))
            .foregroundStyle(.pp(color))
            .fixedSize()
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            LogRow("Upper body", detail: "Thu, Nov 19 · 51 min", spoken: "Upper body")
            LogRow(
                "Dumbbell bench press",
                tag: .gain("+5 lb"),
                figures: "10 × 30 lb/side · 10 × 30 lb/side",
                spoken: "Dumbbell bench press",
            )
            LogRow(
                "Plank",
                tag: .quiet("Same"),
                figures: "1:00 · 1:00 · 0:48",
                detail: "Last set planned at 1:00.",
                spoken: "Plank",
            )
            LogRow("Core", tag: .quiet("16 days ago"), spoken: "Core")
        }
        .padding(.horizontal, Spacing.md)
    }
    .background(Color.pp(.background))
}

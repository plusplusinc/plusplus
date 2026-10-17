import SwiftUI

/// A row's name over an optional detail line, given in parts. With no parts there is no line at
/// all, not an empty one. VoiceOver reads it as one element, "name, detail", with the detail in
/// words when `spokenDetail` is given.
public struct RowLabel: View {
    private let title: String
    private let detail: [String]
    private let spokenDetail: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    public init(
        title: String,
        detail: [String],
        spokenDetail: String? = nil,
    ) {
        self.title = title
        self.detail = detail
        self.spokenDetail = spokenDetail
    }

    /// A row whose detail is one line, or none.
    public init(title: String, detail: String?) {
        self.init(title: title, detail: detail.map { [$0] } ?? [])
    }

    public var body: some View {
        let detailText = Self.detailText(detail, stacked: dynamicTypeSize.isAccessibilitySize)
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
            if let detailText {
                Text(AttributedString.monoNumbers(detailText, font: .ppRowDetailNumber))
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
        // Where its text is on a rail, before it takes the row's width.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowTextFrames.self,
                    value: [proxy.frame(in: .named(RailDrag.space))],
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [title, spokenDetail ?? detail.joined(separator: ", ")]
                .filter { !$0.isEmpty }
                .joined(separator: ", "),
        )
        .hotReloadable()
    }

    /// The detail line from its parts, or nil for none. Joined with dots, each part kept whole,
    /// so a long line wraps between parts; stacked, at the accessibility sizes, a part to a line
    /// with no dots.
    static func detailText(_ parts: [String], stacked: Bool) -> String? {
        guard !parts.isEmpty else { return nil }
        guard !stacked else { return parts.joined(separator: "\n") }
        // The space before a dot is no-break too, so a line never starts with one.
        return parts
            .map { $0.replacingOccurrences(of: " ", with: noBreakSpace) }
            .joined(separator: "\(noBreakSpace)· ")
    }
}

private let noBreakSpace = "\u{00A0}"

#Preview {
    VStack(spacing: Spacing.md) {
        RowLabel(title: "Goblet squat", detail: "Kettlebell")
        RowLabel(
            title: "Dumbbell row",
            detail: ["3 × 10 reps per side", "50 lb"],
        )
        RowLabel(title: "Pigeon stretch", detail: ["60 s per side"])
        RowLabel(title: "Push-up", detail: nil)
    }
    .padding()
    .background(Color.pp(.background))
}

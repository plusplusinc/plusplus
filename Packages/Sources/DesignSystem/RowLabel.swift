import SwiftUI

/// A row's name over an optional detail line, given in parts. With no parts there is no line at
/// all, not an empty one. VoiceOver reads it as one element, "name, detail", with the detail in
/// words when `spokenDetail` is given.
///
/// A row done one side at a time shows a small L | R mark at the end of its name's first line,
/// up to the accessibility sizes. A detail line changed in an animation rolls the digits that
/// changed, up, or down when `detailCountsDown`.
public struct RowLabel: View {
    private let title: String
    private let detail: [String]
    private let spokenDetail: String?
    private let showsSides: Bool
    private let detailCountsDown: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    public init(
        title: String,
        detail: [String],
        spokenDetail: String? = nil,
        showsSides: Bool = false,
        detailCountsDown: Bool = false,
    ) {
        self.title = title
        self.detail = detail
        self.spokenDetail = spokenDetail
        self.showsSides = showsSides
        self.detailCountsDown = detailCountsDown
    }

    /// A row whose detail is one line, or none.
    public init(title: String, detail: String?) {
        self.init(title: title, detail: detail.map { [$0] } ?? [])
    }

    public var body: some View {
        let detailText = Self.detailText(detail, stacked: dynamicTypeSize.isAccessibilitySize)
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(title)
                    .font(.ppRowTitle)
                    .foregroundStyle(.pp(.textPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                // At the accessibility sizes the words "per side", on their own line, say it.
                if showsSides, !dynamicTypeSize.isAccessibilitySize {
                    SidesMark()
                }
            }
            if let detailText {
                Text(detailText)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
                    .contentTransition(.numericText(countsDown: detailCountsDown))
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

/// "L | R" in a small outlined box: done one side at a time. Words on the detail line say it
/// too, so it is hidden from VoiceOver, and it is left out at the accessibility sizes, where it
/// would squeeze the name.
private struct SidesMark: View {
    @ObserveHotReload private var hotReload

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(verbatim: "L")
            Rectangle()
                .fill(.pp(.borderStrong))
                .frame(width: 1)
                .padding(.vertical, Spacing.xxs)
            Text(verbatim: "R")
        }
        .font(.ppSidesMark)
        .foregroundStyle(.pp(.textSecondary))
        .fixedSize()
        .padding(.horizontal, Spacing.xs + Spacing.xxs)
        .padding(.vertical, Spacing.xxs)
        .overlay(RoundedRectangle(cornerRadius: Radius.mark).strokeBorder(.pp(.borderStrong)))
        .accessibilityHidden(true)
        .hotReloadable()
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        RowLabel(title: "Goblet squat", detail: "Kettlebell")
        RowLabel(
            title: "Dumbbell row",
            detail: ["Dumbbells, bench", "3 × 10 reps per side", "50 lb"],
            showsSides: true,
        )
        RowLabel(title: "Pigeon stretch", detail: ["60 s per side"], showsSides: true)
        RowLabel(title: "Push-up", detail: nil)
    }
    .padding()
    .background(Color.pp(.background))
}

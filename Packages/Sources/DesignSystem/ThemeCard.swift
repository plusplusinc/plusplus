import SwiftUI

/// A theme shown as a small current exercise, in that theme's own colors whatever the app is in:
/// the current exercise's green node on the name's line, the theme's name where an exercise's
/// goes (at a row title's size), the current exercise's set segments across the text column
/// under it, one done and two to come, and its looks ("Light and dark", "Dark only") under them
/// in the "Set 2 of 3" caption's style. A card with both looks shows the one the screen's
/// appearance calls for; a dark-only one shows its dark look in either.
///
/// It sits on the theme's background in a rounded card with a hairline of its separator, which
/// shows even on a card whose background is the page's own. Trailing, a mark: a chevron for a
/// card that opens the themes (Settings), or Checklist's pair, an empty circle and a green check,
/// crossfading in place on `.tapChange`, for a card that picks one (the Theme screen). The mark
/// alone says which theme is in use. VoiceOver reads one element: the name, the looks as its
/// value, selected when checked.
public struct ThemeCard: View {
    public enum Mark: Equatable {
        case checked(Bool)
        case opens
    }

    private let theme: Theme
    private let mark: Mark

    @ScaledMetric(relativeTo: .body) private var nodeSize = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 44

    public init(theme: Theme, mark: Mark) {
        self.theme = theme
        self.mark = mark
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        HStack(spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                nodeOnFirstLine
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(theme.name)
                        .font(.ppRowTitle)
                        .foregroundStyle(.pp(.textPrimary))
                    SetSegments(
                        progress: SetProgress(done: 1, total: 3, spoken: ""),
                        isOnSet: false,
                    )
                    Text(theme.looksLine)
                        .font(.ppCurrentProgress)
                        .foregroundStyle(.pp(.textSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            markView
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(shape.fill(.pp(.background)))
        .overlay(shape.strokeBorder(.pp(.separator), lineWidth: 1))
        .contentShape(shape)
        .environment(\.theme, theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.name)
        .accessibilityValue(theme.looksLine)
        .accessibilityAddTraits(mark == .checked(true) ? .isSelected : [])
    }

    /// An exercise row's card radius (`ValueRow`'s): the key's, opened by the row's inner gap.
    private static var cornerRadius: CGFloat {
        Spacing.sm + Radius.key
    }

    /// The current exercise's green node, centered on the name's first line: in a box as tall as
    /// one line of the name at every size.
    private var nodeOnFirstLine: some View {
        ZStack {
            Text(verbatim: "0")
                .font(.ppRowTitle)
                .hidden()
            Circle()
                .fill(.pp(.accent))
                .frame(width: nodeSize, height: nodeSize)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .opens:
            Image(systemName: "chevron.right")
                .font(.ppRowDetail.weight(.semibold))
                .foregroundStyle(.pp(.textSecondary))
        case let .checked(isChecked):
            ZStack {
                Image(systemName: "circle")
                    .foregroundStyle(.pp(.textSecondary))
                    .opacity(isChecked ? 0 : 1)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.pp(.accent))
                    .opacity(isChecked ? 1 : 0)
            }
            .font(.ppCheckMark)
            .animation(.tapChange, value: isChecked)
        }
    }
}

/// A card's press: the card as it is, dimmed while held, as a key and a pill dim
/// (`keyPress(isPressed:)`).
public struct CardButtonStyle: ButtonStyle {
    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.keyPress(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    /// `.buttonStyle(.card)`.
    public static var card: CardButtonStyle {
        CardButtonStyle()
    }
}

#Preview {
    VStack(spacing: Spacing.sm) {
        ThemeCard(theme: .plusPlus, mark: .checked(true))
        ThemeCard(theme: .nord, mark: .checked(false))
        ThemeCard(theme: .nord, mark: .opens)
    }
    .padding(Spacing.md)
    .background(Color.pp(.background))
}

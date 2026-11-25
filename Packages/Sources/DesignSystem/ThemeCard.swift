import SwiftUI

/// A theme shown as a workout's row is drawn, in that theme's own colors whatever the app is in:
/// the current exercise's green node in the rail's column, the theme's name where an exercise's
/// goes, its looks ("Light and dark", "Dark only") as the detail line, with a set's bars at its
/// end, one done in purple and two to do. A card with both looks shows the one the screen's
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
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        HStack(spacing: Spacing.sm) {
            RailRowLayout(nodeSize: nodeSize) {
                RailNodeColumn {
                    Circle()
                        .fill(.pp(.accent))
                        .frame(width: nodeSize, height: nodeSize)
                }
                RowLabel(
                    title: theme.name,
                    detail: [theme.looksLine],
                    bars: SetProgress(done: 1, total: 3, spoken: ""),
                )
            }
            markView
        }
        .padding(.vertical, Spacing.md)
        .padding(.trailing, Spacing.md)
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

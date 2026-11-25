import SwiftUI

/// A theme shown as a small current exercise, in that theme's own colors whatever the app is in:
/// the current exercise's green node on the name's line, the theme's name where an exercise's
/// goes (at a row title's size), the current exercise's set segments across the text column
/// under it, one done and two to come, and its looks ("Light and dark", "Dark only") under them
/// in the "Set 2 of 3" caption's style. It draws the look it is given, `scheme`: a card with both
/// looks shows the one Appearance calls for, whatever theme is in use around it
/// (`Theme.shownScheme(for:phone:)`); a dark-only one shows its dark look in either.
///
/// The node sits `Spacing.md` in from the card's left edge and `Spacing.md` down from its top,
/// still centered on the name's line: the top padding gives up the room the line leaves above
/// the node, and the bottom the same, so the card is that much shorter and the mark stays
/// centered. At accessibility sizes, where the node and the mark have a line of their own above
/// the words, the padding is `Spacing.md` all round.
///
/// It is a rounded card, the exercise sheet's value rows' radius. A card that opens the themes is
/// filled as the value rows are, in `surface`, a step off the page, with no line. A card that
/// picks one sits on its theme's background, the preview; one not in use draws a hairline of its
/// separator only where that background is too close to the page's to show an edge
/// (`edgeContrast`). Trailing,
/// a mark: a chevron for a card that opens the themes (Settings), or, for a card that picks one
/// (the Theme screen), the theme in use outlined in its own green (`accent`), two points, and
/// Checklist's green check, both crossfading in on `.tapChange`; a card not in use has neither,
/// its check's room kept so every name starts and wraps at one place. VoiceOver reads one
/// element: the name, the looks as its value, selected when checked.
public struct ThemeCard: View {
    public enum Mark: Equatable {
        case checked(Bool)
        case opens
    }

    private let theme: Theme
    private let scheme: ColorScheme
    private let mark: Mark

    @ScaledMetric(relativeTo: .body) private var nodeSize = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The height of the node's box, one line of the name (or the node, if taller), as laid out
    /// (`nodeOnFirstLine`).
    @State private var lineHeight: CGFloat = 0
    /// The page around the card: its theme and look, before the card sets its own.
    @Environment(\.self) private var page

    public init(theme: Theme, scheme: ColorScheme, mark: Mark) {
        self.theme = theme
        self.scheme = scheme
        self.mark = mark
    }

    /// Thick enough to read in the theme's green on a card as dark as the page around it and on
    /// one that stands out from it; a point read as the hairline, a little brighter. A step past
    /// today's outline on Log's calendar (1.5), on a much larger shape.
    private static let selectedOutline: CGFloat = 2

    /// The contrast, as WCAG's ratio, under which a card's background shows no edge against the
    /// page's, so it needs the hairline: the value rows' `surface` stands off `background` at
    /// about 1.11 (light) and 1.13 (dark), and reads as a card with no line, so a card at least
    /// that far off reads as one too. PlusPlus dark on Nord is 1.32.
    private static let edgeContrast = 1.1

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The node and the mark on a line of their own above the words, which take the
                // card's whole width: beside them, at AX5, "PlusPlus" had room for "PlusPl…".
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        node
                        Spacer(minLength: 0)
                        markView
                    }
                    words
                }
            } else {
                HStack(spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        nodeOnFirstLine
                        words
                    }
                    markView
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md - verticalSlack)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(shape.fill(.pp(mark == .opens ? .surface : .background)))
        .overlay {
            shape.strokeBorder(.pp(.separator), lineWidth: 1)
                .opacity(needsHairline && !isChecked ? 1 : 0)
                .animation(.tapChange, value: isChecked)
        }
        .overlay {
            shape.strokeBorder(.pp(.accent), lineWidth: Self.selectedOutline)
                .opacity(isChecked ? 1 : 0)
                .animation(.tapChange, value: isChecked)
        }
        .contentShape(shape)
        .environment(\.theme, theme)
        .environment(\.colorScheme, scheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.name)
        .accessibilityValue(theme.looksLine)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private var isChecked: Bool {
        mark == .checked(true)
    }

    /// A picking card whose background is too close to the page's to show where it ends.
    private var needsHairline: Bool {
        guard mark != .opens else { return false }
        var own = page
        own.theme = theme
        own.colorScheme = scheme
        let card = theme.resolve(.background, in: own)
        let around = page.theme.resolve(.background, in: page)
        return DesignSystem.contrast(RGB(card), RGB(around)) < Self.edgeContrast
    }

    /// An exercise row's card radius (`ValueRow`'s): the key's, opened by the row's inner gap.
    private static var cornerRadius: CGFloat {
        Spacing.sm + Radius.key
    }

    /// What the card's top and bottom padding give up so the node's top sits `Spacing.md` from
    /// the card's top edge, as its left does from the left: the room above the node in its
    /// line's box. None at accessibility sizes, where the node has a line of its own.
    private var verticalSlack: CGFloat {
        guard !dynamicTypeSize.isAccessibilitySize else { return 0 }
        return min(max((lineHeight - nodeSize) / 2, 0), Spacing.md)
    }

    /// The current exercise's green node, centered on the name's first line: in a box as tall as
    /// one line of the name at every size. The box's height is read from this layout
    /// (`lineHeight`), never worked out from the font; a size, not a position, which would move
    /// with the pixel grid as the padding it sets moves the card, and loop.
    private var nodeOnFirstLine: some View {
        ZStack {
            Text(verbatim: "0")
                .font(.ppRowTitle)
                .hidden()
            node
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            lineHeight = height
        }
    }

    private var node: some View {
        Circle()
            .fill(.pp(.accent))
            .frame(width: nodeSize, height: nodeSize)
    }

    /// The name, the set segments, and the looks, down the text column. Each wraps between
    /// words where it has to.
    private var words: some View {
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .opens:
            // A filter button's chevron (`FilterLabel`): small, semibold, at the name's size.
            // Forward, so it turns with a right-to-left language.
            Image(systemName: "chevron.forward")
                .font(.ppRowTitle)
                .imageScale(.small)
                .foregroundStyle(.pp(.textSecondary))
                .accessibilityHidden(true)
        case let .checked(isChecked):
            Image(systemName: "checkmark.circle.fill")
                .font(.ppCheckMark)
                .foregroundStyle(.pp(.accent))
                .opacity(isChecked ? 1 : 0)
                .animation(.tapChange, value: isChecked)
                .accessibilityHidden(true)
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
    ScrollView {
        VStack(spacing: Spacing.sm) {
            ThemeCard(theme: .plusPlus, scheme: .dark, mark: .checked(true))
            ThemeCard(theme: .plusPlus, scheme: .light, mark: .checked(false))
            ThemeCard(theme: .nord, scheme: .dark, mark: .checked(false))
            ThemeCard(theme: .nord, scheme: .dark, mark: .opens)
        }
        .padding(Spacing.md)
    }
    .background(Color.pp(.background))
}

#Preview("Long names") {
    // Names to come, for their length.
    ScrollView {
        VStack(spacing: Spacing.sm) {
            ThemeCard(
                theme: Theme(id: "catppuccin", name: "Catppuccin", looks: .catalog),
                scheme: .dark,
                mark: .checked(false),
            )
            ThemeCard(
                theme: Theme(id: "tokyo-night", name: "Tokyo Night", looks: .catalog),
                scheme: .dark,
                mark: .checked(true),
            )
        }
        .padding(Spacing.md)
    }
    .background(Color.pp(.background))
}

import SwiftUI

/// A theme shown as a tiny phone and its name, in that theme's own colors whatever the app is
/// in. At the leading edge, a small picture of the workout screen (`TinyPhone`); beside it, the
/// theme's name at a row title's size and, under it, its looks ("Light and dark", "Dark only")
/// in the "Set 2 of 3" caption's style; trailing, a mark. The phone, the words, and the mark are
/// centered on the card's middle. It draws the look it is given, `scheme`: a card with both
/// looks shows the one Appearance calls for, whatever theme is in use around it
/// (`Theme.shownScheme(for:phone:)`); a dark-only one shows its dark look in either. At
/// accessibility sizes the phone and the mark have a line of their own above the words.
///
/// It is a rounded card, the exercise sheet's value rows' radius, `Spacing.md` in on every side,
/// filled in its theme's `surface`, a step off the page, so the phone, in its `background`,
/// reads as a screen on it. A card that picks a theme and is not in use draws a hairline of its
/// separator only where that fill is too close to the page's background to show an edge
/// (`edgeContrast`). Trailing, a mark: a chevron for a card that opens the themes (Settings),
/// or, for a card that picks one (the Theme screen), the theme in use outlined in its own active
/// color (`accent`), two points, and Checklist's check in it, both crossfading in on `.tapChange`;
/// a
/// card not in use has neither, its check's room kept so every name starts and wraps at one
/// place. VoiceOver reads one element: the name, the looks as its value, selected when checked.
public struct ThemeCard: View {
    public enum Mark: Equatable {
        case checked(Bool)
        case opens
    }

    private let theme: Theme
    private let scheme: ColorScheme
    private let mark: Mark

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The page around the card: its theme and look, before the card sets its own.
    @Environment(\.self) private var page

    public init(theme: Theme, scheme: ColorScheme, mark: Mark) {
        self.theme = theme
        self.scheme = scheme
        self.mark = mark
    }

    /// Thick enough to read in the theme's active color on a card as dark as the page around it and
    /// on
    /// one that stands out from it; a point read as the hairline, a little brighter. A step past
    /// today's outline on Log's calendar (1.5), on a much larger shape.
    private static let selectedOutline: CGFloat = 2

    /// The contrast, as WCAG's ratio, under which a card's fill shows no edge against the page's
    /// background, so it needs the hairline: the value rows' `surface` stands off `background` at
    /// about 1.11 (light) and 1.13 (dark), and reads as a card with no line, so a card at least
    /// that far off reads as one too.
    private static let edgeContrast = 1.1

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The phone and the mark on a line of their own above the words, which take the
                // card's whole width: beside them, at AX5, "PlusPlus" had room for "PlusPl…".
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        TinyPhone()
                        Spacer(minLength: 0)
                        markView
                    }
                    words
                }
            } else {
                HStack(spacing: Spacing.md) {
                    TinyPhone()
                    words
                    markView
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(.pp(.surface)))
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

    /// A picking card whose fill is too close to the page's background to show where it ends.
    private var needsHairline: Bool {
        guard mark != .opens else { return false }
        var own = page
        own.theme = theme
        own.colorScheme = scheme
        let card = theme.resolve(.surface, in: own)
        let around = page.theme.resolve(.background, in: page)
        return DesignSystem.contrast(RGB(card), RGB(around)) < Self.edgeContrast
    }

    /// An exercise row's card radius (`ValueRow`'s): the key's, opened by the row's inner gap.
    private static var cornerRadius: CGFloat {
        Spacing.sm + Radius.key
    }

    /// The name and the looks, down the text column. Each wraps between words where it has to.
    private var words: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(theme.name)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
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

/// A small picture of the workout screen, in the theme and look around it: a phone-shaped
/// rounded rectangle in `background` with a `separator` edge, so it shows on any card; inside,
/// from the top, the current exercise's dot in the active color (`accent`), a bar for its name
/// (`textPrimary`), its three set bars, one done (`done`) and two to come (`toDo`), and at the
/// bottom the key at the foot of the screen (`accent`). A picture: no text, hidden from
/// VoiceOver. Every length is a multiple of the phone's width, which grows with Dynamic Type up
/// to the largest size short of the accessibility sizes (`largest`, about 59 x 97 points), as a
/// list's icons stop growing: past it, the words beside it need the room more than the picture
/// does (at AX5 it had grown to about 122 x 200 points, a third of the screen's height).
struct TinyPhone: View {
    static let largest = DynamicTypeSize.xxxLarge

    var body: some View {
        Picture()
            .dynamicTypeSize(...Self.largest)
    }
}

/// `TinyPhone`, at the text size around it.
private struct Picture: View {
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 44

    /// Points at the default text size; `scale` turns them into this size's.
    private enum Base {
        static let width: CGFloat = 44
        static let height: CGFloat = 72
        static let corner: CGFloat = 9
        static let inset: CGFloat = 7
        static let gap: CGFloat = 5
        static let dot: CGFloat = 7
        static let nameWidth: CGFloat = 22
        static let nameHeight: CGFloat = 3
        static let setHeight: CGFloat = 2
        static let setGap: CGFloat = 2
        static let keyHeight: CGFloat = 10
        static let edge: CGFloat = 1
    }

    private var scale: CGFloat {
        width / Base.width
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Base.corner * scale, style: .continuous)
        VStack(alignment: .leading, spacing: Base.gap * scale) {
            Circle()
                .fill(.pp(.accent))
                .frame(width: Base.dot * scale, height: Base.dot * scale)
            Capsule()
                .fill(.pp(.textPrimary))
                .frame(width: Base.nameWidth * scale, height: Base.nameHeight * scale)
            HStack(spacing: Base.setGap * scale) {
                setBar(.done)
                setBar(.toDo)
                setBar(.toDo)
            }
            Spacer(minLength: 0)
            Capsule()
                .fill(.pp(.accent))
                .frame(height: Base.keyHeight * scale)
        }
        .padding(Base.inset * scale)
        .frame(width: width, height: Base.height * scale, alignment: .topLeading)
        .background(shape.fill(.pp(.background)))
        .overlay(shape.strokeBorder(.pp(.separator), lineWidth: Base.edge))
        .accessibilityHidden(true)
    }

    private func setBar(_ token: ColorToken) -> some View {
        Capsule()
            .fill(.pp(token))
            .frame(maxWidth: .infinity)
            .frame(height: Base.setHeight * scale)
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
    ScrollView {
        VStack(spacing: Spacing.sm) {
            ThemeCard(theme: .catppuccin, scheme: .light, mark: .checked(false))
            ThemeCard(theme: .tokyoNight, scheme: .dark, mark: .checked(true))
        }
        .padding(Spacing.md)
    }
    .background(Color.pp(.background))
}

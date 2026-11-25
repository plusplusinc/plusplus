import SwiftUI

extension Glass {
    /// Regular glass in the theme's tint (`Theme.glassTint(in:)`): the system's own, untinted,
    /// under PlusPlus.
    public static func themed(_ theme: Theme, _ colorScheme: ColorScheme) -> Self {
        .regular.tint(theme.glassTint(in: colorScheme))
    }
}

extension View {
    /// `glassEffect(.regular, in:)` in the theme's tint, read where it is drawn.
    public func themedGlass(interactive: Bool = false, in shape: some Shape) -> some View {
        modifier(ThemedGlass(isInteractive: interactive, shape: shape))
    }
}

extension ToolbarContent {
    /// The bar's shared glass, which takes no tint, hidden under a theme whose glass is tinted,
    /// so the item's own (`themedBarGlass()`) draws in its place rather than inside it.
    public func themedSharedGlass(_ theme: Theme, _ colorScheme: ColorScheme)
        -> some ToolbarContent
    {
        sharedBackgroundVisibility(theme.glassTint(in: colorScheme) == nil ? .automatic : .hidden)
    }
}

extension View {
    /// A bar item's glass in the theme's tint, drawn in place of the bar's shared glass
    /// (`themedSharedGlass(_:_:)`) at the bar's own size: 44 pt tall, at least as wide, a word
    /// inset as the bar insets its buttons. One glass around all the item holds, so it changes
    /// size with what shows rather than one glass crossfading into another. Under PlusPlus,
    /// nothing: the bar's own.
    public func themedBarGlass() -> some View {
        modifier(ThemedBarGlass())
    }
}

private struct ThemedBarGlass: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    func body(content: Content) -> some View {
        if theme.glassTint(in: colorScheme) == nil {
            content
        } else {
            content
                .frame(minWidth: height, minHeight: height)
                // Proposed less than its width, the item's glass came out a 44 pt circle with
                // End squeezed inside it.
                .fixedSize()
                .contentShape(.capsule)
                .themedGlass(interactive: true, in: .capsule)
        }
    }
}

private struct ThemedGlass<GlassShape: Shape>: ViewModifier {
    let isInteractive: Bool
    let shape: GlassShape

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.glassEffect(
            Glass.themed(theme, colorScheme).interactive(isInteractive),
            in: shape,
        )
    }
}

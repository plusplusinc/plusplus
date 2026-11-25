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

extension View {
    /// The bar buttons in it, under a tinted theme: the system's prominent glass
    /// (`.glassProminent`), which the bar draws apart from its shared glass, tinted with
    /// `ThemedBarButton.tint`, their labels in `ThemedBarButton.label` where that is set
    /// (`barLabelStyle(_:)`). A menu takes no prominent glass: the bar draws it in its own
    /// (`themedBarMenu()`). Under PlusPlus, nothing: the bar's own glass.
    public func themedBarButton() -> some View {
        modifier(ThemedBarButton())
    }

    /// A bar button's label in the prominent glass's label color (`themedBarButton()`) where
    /// one is set, else in `own`, else as the button draws it.
    public func barLabelStyle(_ own: ColorToken? = nil) -> some View {
        modifier(BarLabelStyle(own: own))
    }

    /// A menu in a bar under a tinted theme: the bar draws it in its own untinted glass whatever
    /// its style, and colors its label with the tint, so the label takes `textPrimary`, as on
    /// that glass: the prominent glass's label color drew too faint there.
    public func themedBarMenu() -> some View {
        modifier(ThemedBarMenu())
    }
}

nonisolated extension EnvironmentValues {
    /// The color a bar button's label takes on a tinted theme's prominent glass in place of its
    /// own (`themedBarButton()`); none keeps the label's own.
    @Entry public var barLabel: ColorToken?
}

private struct ThemedBarButton: ViewModifier {
    /// The prominent glass's tint, and the color its labels take in place of their own.
    private static let tint: ColorToken = .surface
    private static let label: ColorToken? = nil

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        if environment.theme.glassTint(in: environment.colorScheme) == nil {
            content
        } else {
            content
                .buttonStyle(.glassProminent)
                // Resolved here: the bar resolved a token's color in PlusPlus.
                .tint(Color(Color.pp(Self.tint).resolve(in: environment)))
                .environment(\.barLabel, Self.label)
        }
    }
}

private struct BarLabelStyle: ViewModifier {
    let own: ColorToken?

    @Environment(\.barLabel) private var barLabel

    func body(content: Content) -> some View {
        if let token = barLabel ?? own {
            content.foregroundStyle(.pp(token))
        } else {
            content
        }
    }
}

private struct ThemedBarMenu: ViewModifier {
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        if environment.theme.glassTint(in: environment.colorScheme) == nil {
            content
        } else {
            content.tint(Color(Color.pp(.textPrimary).resolve(in: environment)))
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

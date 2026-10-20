import SwiftUI

/// A place the drawer goes: its icon and name, with no fill or outline, taking taps across the
/// drawer's width. Pressing dims it, as a key does.
public struct DrawerButtonStyle: ButtonStyle {
    /// Comfortably above the 44pt minimum touch target at the default text size.
    private static let minHeight: CGFloat = 48

    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(DrawerLabelStyle())
            .font(.ppDrawerItem)
            .foregroundStyle(.pp(.textPrimary))
            .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .leading)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .keyPressAnimation(isPressed: configuration.isPressed)
            .hotReloadable()
    }
}

/// The icon, then the name, a little apart.
private struct DrawerLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.sm + Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

extension ButtonStyle where Self == DrawerButtonStyle {
    /// `.buttonStyle(.drawer)`.
    public static var drawer: DrawerButtonStyle {
        DrawerButtonStyle()
    }
}

#Preview {
    Button("Routines", systemImage: "rectangle.stack") { }
        .buttonStyle(.drawer)
        .padding()
        .background(Color.pp(.background))
}

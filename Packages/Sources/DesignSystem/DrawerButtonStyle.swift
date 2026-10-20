import SwiftUI

/// A place the drawer goes: its icon and name, with no outline, taking taps across the drawer's
/// width. The place showing sits on a soft rounded fill. Pressing dims it, as a key does.
public struct DrawerButtonStyle: ButtonStyle {
    /// Comfortably above the 44pt minimum touch target at the default text size.
    private static let minHeight: CGFloat = 48
    /// A nested place's smaller text needs less, but never under the 44pt minimum.
    private static let nestedMinHeight: CGFloat = 44

    private let isSelected: Bool
    private let isNested: Bool

    @ObserveHotReload private var hotReload

    public init(isSelected: Bool, isNested: Bool = false) {
        self.isSelected = isSelected
        self.isNested = isNested
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        configuration.label
            .labelStyle(DrawerLabelStyle())
            .font(isNested ? .ppDrawerSubitem : .ppDrawerItem)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Spacing.sm + Spacing.xs)
            .padding(.vertical, Spacing.xs)
            .frame(
                maxWidth: .infinity,
                minHeight: isNested ? Self.nestedMinHeight : Self.minHeight,
                alignment: .leading,
            )
            .background {
                if isSelected {
                    shape.fill(.pp(.surface))
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .keyPressAnimation(isPressed: configuration.isPressed)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    /// `.buttonStyle(.drawer(isSelected: true))`: marked as the place showing; nested, it sits
    /// under another place in smaller text.
    public static func drawer(isSelected: Bool, isNested: Bool = false) -> DrawerButtonStyle {
        DrawerButtonStyle(isSelected: isSelected, isNested: isNested)
    }
}

#Preview {
    VStack(spacing: Spacing.xs) {
        Button("Routines", systemImage: "rectangle.stack") { }
            .buttonStyle(.drawer(isSelected: true))
        Button("New", systemImage: "plus") { }
            .buttonStyle(.drawer(isSelected: false, isNested: true))
    }
    .padding()
    .background(Color.pp(.background))
}

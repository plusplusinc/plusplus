import SwiftUI

/// A place the drawer goes: its icon and name, with no outline, taking taps across the drawer's
/// width. The place showing sits on a soft rounded fill. Pressing dims it, as a key does.
///
/// A nested place, under another, puts its icon (a `DrawerNode`, or a symbol) in the column of
/// the place above's icon, and its name under that place's name; its fill takes the name alone.
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
        configuration.label
            .labelStyle(DrawerLabelStyle(
                isSelected: isSelected,
                isNested: isNested,
                minHeight: isNested ? Self.nestedMinHeight : Self.minHeight,
            ))
            .font(isNested ? .ppDrawerSubitem : .ppDrawerItem)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.leading)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .keyPressAnimation(isPressed: configuration.isPressed)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .hotReloadable()
    }
}

private struct DrawerLabelStyle: LabelStyle {
    let isSelected: Bool
    let isNested: Bool
    let minHeight: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        DrawerLabel(
            icon: configuration.icon,
            title: configuration.title,
            isSelected: isSelected,
            isNested: isNested,
            minHeight: minHeight,
        )
    }
}

/// The icon centered in a column of one width at every level, then the name, a little apart.
private struct DrawerLabel<Icon: View, Title: View>: View {
    let icon: Icon
    let title: Title
    let isSelected: Bool
    let isNested: Bool
    let minHeight: CGFloat

    /// Wide enough for a top-level place's symbol, and scaled with its text.
    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        if isNested {
            HStack(spacing: 0) {
                icon.frame(width: iconColumn)
                title
                    .padding(.horizontal, drawerInset)
                    .padding(.vertical, Spacing.xs)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                    .background {
                        if isSelected {
                            shape.fill(.pp(.surface))
                        }
                    }
            }
            .padding(.leading, drawerInset)
        } else {
            HStack(spacing: 0) {
                icon.frame(width: iconColumn)
                title.padding(.leading, drawerInset)
            }
            .padding(.horizontal, drawerInset)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background {
                if isSelected {
                    shape.fill(.pp(.surface))
                }
            }
        }
    }
}

/// How far a place's icon sits from the drawer's edge, and its name from the icon.
private let drawerInset = Spacing.sm + Spacing.xs

/// A nested place's node, the rail's dot: brighter for the place showing.
public struct DrawerNode: View {
    private let isLit: Bool
    @ScaledMetric(relativeTo: .body) private var size = railNodeSize

    public init(isLit: Bool) {
        self.isLit = isLit
    }

    public var body: some View {
        Circle()
            .fill(.pp(isLit ? .textPrimary : .rail))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
            .buttonStyle(.drawer(isSelected: false))
        Button { } label: {
            Label { Text(verbatim: "Leg day") } icon: { DrawerNode(isLit: true) }
        }
        .buttonStyle(.drawer(isSelected: true, isNested: true))
        Button { } label: {
            Label { Text(verbatim: "Push day") } icon: { DrawerNode(isLit: false) }
        }
        .buttonStyle(.drawer(isSelected: false, isNested: true))
        Button("New", systemImage: "plus") { }
            .buttonStyle(.drawer(isSelected: false, isNested: true))
    }
    .padding()
    .background(Color.pp(.background))
}

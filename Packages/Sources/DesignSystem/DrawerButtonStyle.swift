import SwiftUI

/// A place the drawer goes: its icon and name, with no outline, taking taps across the drawer's
/// width. The place showing sits on a rounded fill, icon and name, with as much space to the
/// icon's left as above and below it. Pressing dims it, as a key does.
public struct DrawerButtonStyle: ButtonStyle {
    private let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(DrawerLabelStyle(isSelected: isSelected))
            .font(.ppDrawerItem)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.leading)
            .contentShape(.rect)
            .keyPress(isPressed: configuration.isPressed)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DrawerLabelStyle: LabelStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        DrawerLabel(icon: configuration.icon, title: configuration.title, isSelected: isSelected)
    }
}

/// The icon centered in a column of one width for every place, then the name, a little apart.
private struct DrawerLabel<Icon: View, Title: View>: View {
    let icon: Icon
    let title: Title
    let isSelected: Bool

    /// The minimum touch target, for every place alike.
    private let minHeight: CGFloat = 44

    /// Wide enough for a place's symbol, and scaled with its text.
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            icon
                .anchorPreference(key: DrawerIconBounds.self, value: .bounds) { $0 }
                .frame(width: iconColumn)
            // A place is one word, which at the largest sizes would break mid-word beside its
            // icon; it shrinks a little to stay whole instead.
            title
                .lineLimit(1)
                .minimumScaleFactor(placeNameScale)
                .padding(.leading, drawerInset)
        }
        .padding(.leading, iconLead)
        .padding(.trailing, fillTrailingInset + drawerInset)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .backgroundPreferenceValue(DrawerIconBounds.self) { anchor in
            if isSelected, let anchor {
                GeometryReader { proxy in
                    fill(around: proxy[anchor], in: proxy.size)
                }
            }
        }
    }

    /// The fill of the place showing: as much space to the icon's left as above and below it,
    /// so the icon sits evenly inside its corner, and inset from the drawer's trailing edge.
    private func fill(around icon: CGRect, in size: CGSize) -> some View {
        let leading = max(0, icon.minX - icon.minY)
        return RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
            .fill(.pp(.selectionFill))
            .frame(width: max(0, size.width - fillTrailingInset - leading), height: size.height)
            .offset(x: leading)
    }
}

/// The bounds of a place's icon as drawn, which its fill keeps an even space around.
private struct DrawerIconBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// How far a place's name may shrink to fit on its line.
private let placeNameScale: CGFloat = 0.7

/// How far a place's name sits from its icon's column.
private let drawerInset = Spacing.sm + Spacing.xs

/// How far a place's icon column sits in from the row's leading edge: far enough that the fill
/// of the place showing, its icon's vertical space to its left, stays clear of the drawer's edge.
private let iconLead: CGFloat = 17

/// How far the fill of the place showing stops short of the row's trailing edge.
private let fillTrailingInset = Spacing.sm

extension ButtonStyle where Self == DrawerButtonStyle {
    /// `.buttonStyle(.drawer(isSelected: true))`: marked as the place showing.
    public static func drawer(isSelected: Bool) -> DrawerButtonStyle {
        DrawerButtonStyle(isSelected: isSelected)
    }
}

#Preview {
    VStack(spacing: Spacing.xs) {
        Button("Routine", systemImage: "checklist") { }
            .buttonStyle(.drawer(isSelected: true))
        Button("Routine", systemImage: "checklist") { }
            .buttonStyle(.drawer(isSelected: false))
    }
    .padding()
    .background(Color.pp(.background))
}

extension View {
    /// A key's press, dimmed: dimming, not scaling, so nothing around it moves.
    func keyPress(isPressed: Bool) -> some View {
        opacity(isPressed ? 0.6 : 1).keyPressAnimation(isPressed: isPressed)
    }

    /// A key's press: down at once, as a finger lands, and back up quickly on release. Left to
    /// the system, the release eased back over half a second.
    func keyPressAnimation(isPressed: Bool) -> some View {
        animation(isPressed ? nil : .snappy(duration: 0.15), value: isPressed)
    }
}

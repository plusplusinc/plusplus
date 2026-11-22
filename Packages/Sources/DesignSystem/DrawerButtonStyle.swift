import SwiftUI

/// A place the drawer goes: its icon and name, with no outline, taking taps across the drawer's
/// width. The place showing sits on a rounded fill, icon and name, with as much space to the
/// icon's left as above and below it. A press shows nothing of its own: the mark sliding to
/// the place tapped is the answer, and a dim or a fill under the finger read as a second,
/// weaker sign beside it.
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
    /// Within `drawerMarks()` it is one mark that slides from row to row as the place changes
    /// inside an animation; the row it leaves drops its own at once, so no second fill fades.
    private func fill(around icon: CGRect, in size: CGSize) -> some View {
        fillShape(around: icon, in: size)
            .modifier(DrawerMarkMatch())
            .transition(.identity)
    }

    private func fillShape(around icon: CGRect, in size: CGSize) -> some View {
        let leading = max(0, icon.minX - icon.minY)
        return RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
            .fill(.pp(.selectionFill))
            .frame(width: max(0, size.width - fillTrailingInset - leading), height: size.height)
            .padding(.leading, leading)
    }
}

/// One mark across a drawer's places, where `drawerMarks()` gives them a namespace.
private struct DrawerMarkMatch: ViewModifier {
    @Environment(\.drawerMarkSpace) private var space

    func body(content: Content) -> some View {
        if let space {
            content.matchedGeometryEffect(id: "mark", in: space)
        } else {
            content
        }
    }
}

extension View {
    /// Makes the mark of the place showing, across the drawer places inside, one mark that
    /// slides from the old place to the new as the place changes inside an animation.
    public func drawerMarks() -> some View {
        modifier(DrawerMarkSpace())
    }
}

private struct DrawerMarkSpace: ViewModifier {
    @Namespace private var space

    func body(content: Content) -> some View {
        content.environment(\.drawerMarkSpace, space)
    }
}

extension EnvironmentValues {
    @Entry var drawerMarkSpace: Namespace.ID?
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
        Button("Workouts", systemImage: "checklist") { }
            .buttonStyle(.drawer(isSelected: true))
        Button("Workouts", systemImage: "checklist") { }
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

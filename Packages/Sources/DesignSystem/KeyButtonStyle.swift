import SwiftUI

/// A full-width, key-shaped button: surface fill, strong outline, label leading.
///
/// A label's icon is centered in the rail column, the leading strip where a list's rows put
/// their markers, so the button lines up with the rows above it. Pressing dims the button
/// rather than scaling it, so nothing around it moves.
public struct KeyButtonStyle: ButtonStyle {
    /// Comfortably above the 44pt minimum touch target at the default text size.
    private static let minHeight: CGFloat = 48

    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(RailIconLabelStyle())
            .font(.ppButton)
            .foregroundStyle(.pp(.textPrimary))
            .padding(.vertical, Spacing.sm)
            .padding(.trailing, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .leading)
            .keyFace(isPressed: configuration.isPressed)
            .hotReloadable()
    }
}

/// The icon in the rail column, the title after it.
private struct RailIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            configuration.icon.railColumn()
            configuration.title
        }
    }
}

extension View {
    /// A key's face: surface fill and strong outline, dimmed while pressed, and further when it
    /// can't be used.
    func keyFace(isPressed: Bool, isEnabled: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        return background(shape.fill(.pp(.surface)))
            .overlay(shape.strokeBorder(.pp(.borderStrong)))
            .contentShape(shape)
            .opacity(isEnabled ? (isPressed ? 0.6 : 1) : 0.35)
            .keyPressAnimation(isPressed: isPressed)
    }

    /// A key's press: down at once, as a finger lands, and back up quickly on release. Left to
    /// the system, the release eased back over half a second.
    func keyPressAnimation(isPressed: Bool) -> some View {
        animation(isPressed ? nil : .snappy(duration: 0.15), value: isPressed)
    }
}

extension ButtonStyle where Self == KeyButtonStyle {
    /// `.buttonStyle(.key)`.
    public static var key: KeyButtonStyle {
        KeyButtonStyle()
    }
}

#Preview {
    Button("Add exercise", systemImage: "plus") { }
        .buttonStyle(.key)
        .padding()
        .background(Color.pp(.background))
}

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
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        configuration.label
            .labelStyle(RailIconLabelStyle())
            .font(.ppButton)
            .foregroundStyle(.pp(.textPrimary))
            .padding(.vertical, Spacing.sm)
            .padding(.trailing, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .leading)
            .background(shape.fill(.pp(.surface)))
            .overlay(shape.strokeBorder(.pp(.borderStrong)))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .hotReloadable()
    }
}

/// The icon in the rail column, the title after it.
private struct RailIconLabelStyle: LabelStyle {
    /// The rail column's width. At large text sizes it grows with the icon, keeping an inset,
    /// rather than clipping it.
    private static let railColumnWidth: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            configuration.icon
                .padding(.horizontal, Spacing.sm)
                .frame(minWidth: Self.railColumnWidth)
            configuration.title
        }
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

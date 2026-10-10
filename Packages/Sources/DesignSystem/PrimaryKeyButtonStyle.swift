import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill on a ledge, label
/// leading. Pressing pushes the key down onto its ledge, which stays put, so nothing around it
/// moves. Not green: green is for data.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .title2) private var minHeight: CGFloat = 72
    private static let ledge: CGFloat = 4

    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        configuration.label
            .ppPrimaryKeyFont()
            .foregroundStyle(.pp(.onPrimaryKey))
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(shape.fill(.pp(.primaryKey)))
            .contentShape(shape)
            .offset(y: configuration.isPressed ? Self.ledge : 0)
            .background(shape.fill(.pp(.borderStrong)).offset(y: Self.ledge))
            .padding(.bottom, Self.ledge)
            .hotReloadable()
    }
}

extension ButtonStyle where Self == PrimaryKeyButtonStyle {
    /// `.buttonStyle(.primaryKey)`.
    public static var primaryKey: PrimaryKeyButtonStyle {
        PrimaryKeyButtonStyle()
    }
}

#Preview {
    Button("Start", systemImage: "play.fill") { }
        .buttonStyle(.primaryKey)
        .padding()
        .background(Color.pp(.background))
}

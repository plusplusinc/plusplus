import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill on a ledge, label
/// leading. Pressing pushes the key down onto its ledge, which stays put, so nothing around it
/// moves. Not green: green is for data.
///
/// Its corners are concentric with its container's, the screen's in `primaryKeyBar`; the
/// radius is resolved once, from where the key sits, and the ledge takes the same shape.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    /// A little taller than a key, such as Add exercise.
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 56
    private static let ledge: CGFloat = 4

    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = ConcentricRectangle(
            corners: .concentric(minimum: .fixed(Radius.key)),
            isUniform: true,
        )
        configuration.label
            .font(.ppPrimaryKey)
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

extension View {
    /// A screen's primary key in a bar at its bottom while `isPresented`, rising in and dropping
    /// out. The key sits as far from the screen's bottom edge as from its sides, below the home
    /// indicator's safe area, so its corners are concentric with the screen's, as the system's
    /// bottom buttons are.
    public func primaryKeyBar(isPresented: Bool, @ViewBuilder key: () -> some View) -> some View {
        let key = key()
        return safeAreaBar(edge: .bottom) {
            if isPresented {
                key
                    .buttonStyle(.primaryKey)
                    .padding([.horizontal, .bottom], Spacing.md)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

#Preview {
    Button("Start", systemImage: "play.fill") { }
        .buttonStyle(.primaryKey)
        .padding()
        .background(Color.pp(.background))
}

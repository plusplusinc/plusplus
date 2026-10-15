import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill, label
/// centered. Pressing pushes the key down onto its plate, which stays put, so nothing around it
/// moves. Not green: green is for data.
///
/// A key's shape, as Add exercise's is, raised on a plate of the same shape.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    /// A little taller than a key, such as Add exercise.
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 56

    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ppPrimaryKey)
            .foregroundStyle(.pp(.onPrimaryKey))
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .raisedKey(fill: .pp(.primaryKey), isPressed: configuration.isPressed)
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
    /// out. The key sits above the home indicator, inset from the screen's sides as the content
    /// above it is, on a floor of the screen's background that runs to the bottom edge: content
    /// scrolled under the bar shows neither beside the key nor below it.
    public func primaryKeyBar(isPresented: Bool, @ViewBuilder key: () -> some View) -> some View {
        let key = key()
        return safeAreaBar(edge: .bottom) {
            if isPresented {
                key
                    .buttonStyle(.primaryKey)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .background { Color.pp(.background).ignoresSafeArea() }
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

#Preview("Bar") {
    Color.pp(.background)
        .ignoresSafeArea()
        .primaryKeyBar(isPresented: true) {
            Button("Start", systemImage: "play.fill") { }
        }
}

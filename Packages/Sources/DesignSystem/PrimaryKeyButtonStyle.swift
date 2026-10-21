import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill on a ledge, label
/// centered. Pressing pushes the key down onto its ledge, which stays put, so nothing around it
/// moves, with a medium impact as the finger lands. Not green: green is for data.
///
/// A key's shape, as Add exercise's is, on a ledge of the same shape.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    /// A little taller than a key, such as Add exercise.
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 56
    private static let ledge: CGFloat = 4

    /// Held down on its ledge after the press, as Start is while it leaves.
    private let isPressedIn: Bool

    @ObserveHotReload private var hotReload

    public init(isPressedIn: Bool = false) {
        self.isPressedIn = isPressedIn
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        let isDown = configuration.isPressed || isPressedIn
        configuration.label
            .font(.ppPrimaryKey)
            .foregroundStyle(.pp(.onPrimaryKey))
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(shape.fill(.pp(.primaryKey)))
            .contentShape(shape)
            .offset(y: isDown ? Self.ledge : 0)
            .keyPressAnimation(isPressed: isDown)
            .background(shape.fill(.pp(.borderStrong)).offset(y: Self.ledge))
            .padding(.bottom, Self.ledge)
            .sensoryFeedback(
                .impact(weight: .medium),
                trigger: configuration.isPressed,
            ) { _, isDown in
                isDown
            }
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
    /// out, or with Reduce Motion fading in and out. The key sits above the home indicator, inset
    /// from the screen's sides as the content
    /// above it is, on a floor of the screen's background that runs to the bottom edge: content
    /// scrolled under the bar shows neither beside the key nor below it. `isPressedIn` holds the
    /// key down after its press, so it leaves pressed.
    public func primaryKeyBar(
        isPresented: Bool,
        isPressedIn: Bool = false,
        @ViewBuilder key: () -> some View,
    ) -> some View {
        let key = key()
        return safeAreaBar(edge: .bottom) {
            if isPresented {
                key
                    .buttonStyle(PrimaryKeyButtonStyle(isPressedIn: isPressedIn))
                    .hiddenBehindDrawer()
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .background { Color.pp(.background).ignoresSafeArea() }
                    .transition(KeyFloorTransition())
            }
        }
    }
}

/// The key and its floor sliding off the bottom as they fade, or, with Reduce Motion, only
/// fading.
private struct KeyFloorTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(KeyFloorPlace(isShown: phase.isIdentity))
    }
}

private struct KeyFloorPlace: ViewModifier {
    let isShown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isDown = !isShown && !reduceMotion
        content
            .visualEffect { content, proxy in
                content.offset(y: isDown ? proxy.size.height : 0)
            }
            .opacity(isShown ? 1 : 0)
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

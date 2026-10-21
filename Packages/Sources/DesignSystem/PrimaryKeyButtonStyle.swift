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
    /// from the screen's sides as the content above it is, with nothing behind it: a scroll
    /// view's content runs on under the key, beside and below it, softened by the system's
    /// scroll edge effect, which a `safeAreaBar` extends to its height as the navigation bar's
    /// does at the top. `isPressedIn` holds the key down after its press, so it leaves pressed: a
    /// +1 pops off its top as it goes down, and a light impact plays as it starts to leave.
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
                    .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) { $0 }
                    .hiddenBehindDrawer()
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .transition(KeyBarTransition())
            }
        }
        // Over the screen rather than in the bar: the bar's scroll edge effect grows to cover
        // whatever the bar draws, so a +1 rising in it raised a frosted band behind itself.
        .overlayPreferenceValue(PrimaryKeyBounds.self) { key in
            GeometryReader { proxy in
                if let key {
                    let bounds = proxy[key]
                    PlusOneBurst(isOn: isPressedIn)
                        .frame(width: bounds.width, height: max(bounds.minY, 0), alignment: .bottom)
                        .offset(x: bounds.minX)
                }
            }
            .allowsHitTesting(false)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isPresented) { wasShown, isShown in
            wasShown && !isShown && isPressedIn
        }
    }
}

/// Where the primary key is, for the +1 that pops off its top.
private struct PrimaryKeyBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The key sliding off the bottom as it fades, or, with Reduce Motion, only fading.
private struct KeyBarTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(KeyBarPlace(isShown: phase.isIdentity))
    }
}

private struct KeyBarPlace: ViewModifier {
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

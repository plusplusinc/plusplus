import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill on a ledge, label
/// centered. Pressing pushes the key down onto its ledge, which stays put, so nothing around it
/// moves, and letting go lets it back up, each in 0.06 s, easing out. Not green: green is for
/// data.
///
/// A key's shape, as Add exercise's is, on a ledge of the same shape.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    /// A little taller than a key, such as Add exercise.
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 56
    private static let ledge: CGFloat = 4
    /// The press and the release: a quick ease-out both ways, so the key reads as struck.
    private static let press = Animation.easeOut(duration: 0.06)

    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        configuration.label
            .font(.ppPrimaryKey)
            .foregroundStyle(.pp(.onPrimaryKey))
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(shape.fill(.pp(.primaryKey)))
            .contentShape(shape)
            .offset(y: configuration.isPressed ? Self.ledge : 0)
            .animation(Self.press, value: configuration.isPressed)
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
    /// out, or with Reduce Motion fading in and out. The key sits above the home indicator, inset
    /// from the screen's sides as the content above it is, with nothing behind it: a scroll
    /// view's content runs on under the key, beside and below it, softened by the system's
    /// scroll edge effect, which a `safeAreaBar` extends to its height as the navigation bar's
    /// does at the top. As `plusOne` turns on, a +1 pops off the key's top with a medium impact.
    /// `drop` moves the key down by that much, at least off the screen, which an animation
    /// carries it along at its own pace.
    public func primaryKeyBar(
        isPresented: Bool,
        plusOne: Bool = false,
        drop: CGFloat = 0,
        @ViewBuilder key: () -> some View,
    ) -> some View {
        let key = key()
        return safeAreaBar(edge: .bottom) {
            if isPresented {
                key
                    .buttonStyle(.primaryKey)
                    .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) { $0 }
                    .modifier(KeyDrop(drop: drop))
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
                    PlusOneBurst(isOn: plusOne)
                        .frame(width: bounds.width, height: max(bounds.minY, 0), alignment: .bottom)
                        .offset(x: bounds.minX)
                }
            }
            .allowsHitTesting(false)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: plusOne) { wasOn, isOn in
            !wasOn && isOn
        }
    }
}

/// The key moved down by `drop`, at least out of sight: by its own height and what lies below it.
/// Animatable, so the drop is worked out frame by frame alongside the layout of a list it rides
/// with; animated as an offset, it ran two frames ahead of the list's rows.
private struct KeyDrop: ViewModifier, Animatable {
    let drop: CGFloat
    /// How far along the drop the key is, 0 to 1, which an animation runs through.
    var progress: CGFloat

    init(drop: CGFloat) {
        self.drop = drop
        progress = drop > 0 ? 1 : 0
    }

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @State private var exit: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: progress * max(drop, exit))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height + proxy.safeAreaInsets.bottom
            } action: { exit = $0 + Spacing.sm }
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

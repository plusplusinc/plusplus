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
    /// A screen's primary key in a bar at its bottom while `isPresented`, sliding up in from
    /// below the screen's edge and down out of it as it fades, or with Reduce Motion fading in
    /// and out. The key sits above the home indicator, with nothing behind it: a scroll view's
    /// content runs on under the key, beside and below it, softened by the system's scroll edge
    /// effect, which a `safeAreaBar` extends to its height as the navigation bar's does at the
    /// top. Its sides are as far from the screen's edges as its bottom is from the screen's
    /// bottom. As `plusOne` turns on, a +1 pops off the key's top with a medium impact. `drop`
    /// moves the key down by that much, at least off the screen, which an animation carries it
    /// along at its own pace.
    public func primaryKeyBar(
        isPresented: Bool,
        plusOne: Bool = false,
        drop: CGFloat = 0,
        @ViewBuilder key: () -> some View,
    ) -> some View {
        modifier(PrimaryKeyBar(isPresented: isPresented, plusOne: plusOne, drop: drop, key: key()))
    }
}

private struct PrimaryKeyBar<Key: View>: ViewModifier {
    let isPresented: Bool
    let plusOne: Bool
    let drop: CGFloat
    let key: Key

    /// The screen's bottom safe area, less the keyboard's, measured on the screen rather than on
    /// the key, so a key coming in has it from its first frame: measured on the key, it came in
    /// 16 pt from the sides, then narrowed to its place on the screen's next animation.
    @State private var bottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaBar(edge: .bottom) {
                if isPresented {
                    key
                        .buttonStyle(.primaryKey)
                        .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) { $0 }
                        .modifier(KeyDrop(drop: drop, isDropped: drop > 0))
                        .hiddenBehindDrawer()
                        // As far from the sides as from the bottom; with no home indicator, as
                        // far as content is inset.
                        .padding(.horizontal, bottomInset > 0 ? bottomInset : Spacing.md)
                        .padding(.top, Spacing.sm)
                        .transition(KeyBarTransition(below: bottomInset))
                }
            }
            // The screen's own inset, without the keyboard's when it is up: with the keyboard's
            // height as the side insets, the key stood tall and narrow over it, and the bar,
            // wider than the screen, pushed the whole screen off its left edge. Measured inside
            // the view that ignores the keyboard, which takes its inset away from what it holds;
            // measured on that view, the keyboard's inset still counted.
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) {
                        bottomInset = $0
                    }
                    .ignoresSafeArea(.keyboard)
            }
            // Over the screen rather than in the bar: the bar's scroll edge effect grows to cover
            // whatever the bar draws, so a +1 rising in it raised a frosted band behind itself.
            .overlayPreferenceValue(PrimaryKeyBounds.self) { key in
                GeometryReader { proxy in
                    if let key {
                        let bounds = proxy[key]
                        PlusOneBurst(isOn: plusOne)
                            .frame(
                                width: bounds.width,
                                height: max(bounds.minY, 0),
                                alignment: .bottom,
                            )
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

    init(drop: CGFloat, isDropped: Bool) {
        self.drop = drop
        progress = isDropped ? 1 : 0
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

/// The key coming up from below the screen's edge, unfaded, and going back down as it fades;
/// with Reduce Motion, only fading. `below` is how far the screen runs on below the bar.
private struct KeyBarTransition: Transition {
    let below: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(KeyBarPlace(phase: phase, below: below))
    }
}

private struct KeyBarPlace: ViewModifier {
    let phase: TransitionPhase
    let below: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isFaded = phase == .didDisappear || (reduceMotion && !phase.isIdentity)
        KeyRise(progress: phase.isIdentity || reduceMotion ? 1 : 0, below: below) {
            content
        }
        .opacity(isFaded ? 0 : 1)
    }
}

/// The key `progress` of the way up from below the screen's edge, the bar as tall as the key
/// stands above the bar's bottom, so the bar's edge band rises with the key's top rather than
/// standing at full height from the first frame. A layout, so the bar's height, and the band
/// with it, is worked out frame by frame with the key.
private struct KeyRise: Layout {
    var progress: CGFloat
    let below: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width, height: max(size.height - hidden(size.height), 0))
    }

    nonisolated func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard let key = subviews.first else { return }
        let size = key.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        key.place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - size.height + hidden(size.height)),
            proposal: ProposedViewSize(width: bounds.width, height: size.height),
        )
    }

    /// How far down the key is: none at rest, out of sight below the screen at 0.
    private nonisolated func hidden(_ height: CGFloat) -> CGFloat {
        (1 - progress) * (height + below)
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

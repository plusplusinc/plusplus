import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill on a ledge, label
/// centered. Pressing pushes the key down onto its ledge, which stays put, so nothing around it
/// moves, and letting go lets it back up, each in 0.06 s, easing out. Not green: green is for
/// data and the + that floats above it.
///
/// A capsule, its ends fully round, on a ledge of the same shape. A label that wraps, at the
/// largest text sizes, makes the key taller with the same round corners and straight sides
/// between them: as a capsule it went oval, and the label's first and last lines stood out past
/// its edge. At the accessibility sizes the label's side padding is smaller, so a short label, as
/// an exercise's name on the way back, stays on one line and the key a capsule; with none, a
/// label that just fit ran into the round ends.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: Self.textStyle) private var minHeight = Self.faceHeight
    /// Above and below the label, inside the minimum height for one line, so a wrapped label's
    /// first and last lines stay clear of the round corners.
    @ScaledMetric(relativeTo: Self.textStyle) private var labelInset: CGFloat = 12
    /// The face's height for one line of label, at the default text size: with its ledge, as tall
    /// as a tab bar floats, measured on the Files app's on iOS 27.2.
    fileprivate static let faceHeight: CGFloat = 58
    /// What `faceHeight` scales with: the label's text style.
    fileprivate static let textStyle = Font.TextStyle.title3
    /// How far the key goes down onto its ledge when pressed, and how far the ledge shows below it.
    fileprivate static let ledge: CGFloat = 4
    /// In `primaryKeyBar`, how far the key's ledge sits above the screen's bottom, and the key
    /// from its sides: where a tab bar floats, measured on the Files app's on iOS 27.2. Not
    /// concentric with the screen's corners, as a tab bar isn't either.
    fileprivate static let lowInset: CGFloat = 21
    /// In `primaryKeyBar`, between the key's top and the floating button's bottom.
    fileprivate static let floatingGap = Spacing.md
    /// In `primaryKeyBar`, the room above the key's face, inside the bar.
    fileprivate static let barTop = Spacing.sm
    /// The press and the release: a quick ease-out both ways, so the key reads as struck.
    private static let press = Animation.easeOut(duration: 0.06)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: minHeight / 2)
        configuration.label
            .font(.ppPrimaryKey)
            .foregroundStyle(.pp(.onPrimaryKey))
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Spacing.md : Spacing.lg)
            .padding(.vertical, labelInset)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(shape.fill(.pp(.primaryKey)))
            .contentShape(shape)
            .offset(y: configuration.isPressed ? Self.ledge : 0)
            .animation(Self.press, value: configuration.isPressed)
            .background(shape.fill(.pp(.borderStrong)).offset(y: Self.ledge))
            .padding(.bottom, Self.ledge)
    }
}

extension ButtonStyle where Self == PrimaryKeyButtonStyle {
    /// `.buttonStyle(.primaryKey)`.
    public static var primaryKey: PrimaryKeyButtonStyle {
        PrimaryKeyButtonStyle()
    }
}

extension PrimaryKeyButtonStyle {
    /// Each half of a bar's key swapping for another: the key going down and out, then the next
    /// coming up and in.
    public static let swapHalf = 0.2
}

extension View {
    /// A screen's primary key in a bar at its bottom while `isPresented`, sliding up in from
    /// below the screen's edge and down out of it as it fades, or with Reduce Motion fading in
    /// and out. The key sits above the home indicator, with nothing behind it: a scroll view's
    /// content runs on under the key, beside and below it, with the bottom scroll edge effect
    /// hidden, which a `safeAreaBar` would otherwise draw behind the bar. It sits where a tab bar
    /// floats: its ledge's bottom 21 pt above the screen's bottom, and its sides 21 pt from the
    /// screen's. Each time `plusOnes` goes up, a +1 pops off the key's top. `drop` moves the key
    /// down by that much, at least off the screen, which an animation carries it along at its own
    /// pace.
    ///
    /// `floating`, a button drawn in the `floating` style, floats above the key's right end, its
    /// right edge on the key's and 16 pt above the key's top, whether the key shows or not: with
    /// none, it is where it is above a key of one line, so a key coming in leaves it where it is.
    /// While `floatsLow`, as on a screen with nothing for the key to do yet, it sits low instead,
    /// its bottom where the key's ledge's bottom would be, and rises above the key, or comes
    /// back down, on the update that changes `floatsLow`, with the key's rise or drop when the
    /// same update presents or takes it away.
    /// It takes no room from the content: a list under it leaves `FloatingButtonRoom` at its end.
    ///
    /// `key` draws `face`, the key as things stand. A face of another `id` is another key, which
    /// the bar swaps in on its own (`KeyStage`): the one showing goes down out of the screen's
    /// bottom edge with its words as they were, then the next comes up in from it, each in
    /// `PrimaryKeyButtonStyle.swapHalf`, never two keys at once and never both words on one;
    /// with Reduce Motion, each fades. The bar keeps its room throughout, so the list under it
    /// stays put: with the bar gone between them, a list at its end moved down. While it swaps,
    /// `key` is told it is out (`isOut`), and its action does nothing then: the key stays
    /// enabled, as VoiceOver reads it, rather than dimmed for the swap's length. Within one id,
    /// the words change in place. A face that changes
    /// while the key is not presented, or while `drop` has it out of sight, comes back as the
    /// new key, with no swap, under the animation that brings it back. While
    /// `keepsRoom`, a key not presented still holds its room in the bar, unseen, so the list's
    /// bottom inset stays as the key goes and comes back.
    public func primaryKeyBar<Face: Equatable & Identifiable, Key: View>(
        isPresented: Bool,
        face: Face,
        keepsRoom: Bool = false,
        plusOnes: Int = 0,
        drop: CGFloat = 0,
        floatsLow: Bool = false,
        @ViewBuilder key: @escaping (Face, _ isOut: Bool) -> Key,
        @ViewBuilder floating: () -> some View = { EmptyView() },
    ) -> some View {
        modifier(PrimaryKeyBar(
            isPresented: isPresented,
            face: face,
            keepsRoom: keepsRoom,
            plusOnes: plusOnes,
            drop: drop,
            floatsLow: floatsLow,
            key: key,
            floating: floating(),
        ))
    }

    /// A bar whose key is always the same one, as Start alone.
    public func primaryKeyBar(
        isPresented: Bool,
        keepsRoom: Bool = false,
        plusOnes: Int = 0,
        drop: CGFloat = 0,
        floatsLow: Bool = false,
        @ViewBuilder key: () -> some View,
        @ViewBuilder floating: () -> some View = { EmptyView() },
    ) -> some View {
        let key = key()
        return primaryKeyBar(
            isPresented: isPresented,
            face: OneFace(),
            keepsRoom: keepsRoom,
            plusOnes: plusOnes,
            drop: drop,
            floatsLow: floatsLow,
            key: { _, _ in key },
            floating: floating,
        )
    }
}

/// The face of a bar with one key.
private struct OneFace: Equatable, Identifiable {
    var id: Int {
        0
    }
}

private struct PrimaryKeyBar<
    Face: Equatable & Identifiable,
    Key: View,
    Floating: View,
>: ViewModifier {
    let isPresented: Bool
    let face: Face
    let keepsRoom: Bool
    let plusOnes: Int
    let drop: CGFloat
    let floatsLow: Bool
    let key: (Face, _ isOut: Bool) -> Key
    let floating: Floating

    /// The screen's bottom safe area, less the keyboard's, measured on the screen rather than on
    /// the key, so a key coming in has it from its first frame: measured on the key, it came in
    /// 16 pt from the sides, then narrowed to its place on the screen's next animation.
    @State private var bottomInset: CGFloat = 0
    /// The screen's bottom safe area with the keyboard's: more than `bottomInset` while the
    /// keyboard is up, which the bar then sits on.
    @State private var keyboardInset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The key's inset from the screen's sides: `lowInset`, and with no home indicator, as far as
    /// content is inset. At the accessibility sizes, as far as content is inset, so its label
    /// has the width to stay on one line.
    private var sideInset: CGFloat {
        bottomInset > 0 && !dynamicTypeSize.isAccessibilitySize
            ? PrimaryKeyButtonStyle.lowInset
            : Spacing.md
    }

    /// The ledge's bottom above the screen's bottom: `lowInset`, and with no home indicator, the
    /// bar's own bottom.
    private var ledgeLift: CGFloat {
        bottomInset > 0 ? PrimaryKeyButtonStyle.lowInset : 0
    }

    private var isOnKeyboard: Bool {
        keyboardInset > bottomInset
    }

    /// How far below its place in the bar the key is drawn: down to its ledge's place, or on the
    /// keyboard, up by its ledge.
    private var drawnLower: CGFloat {
        (isOnKeyboard ? 0 : bottomInset - ledgeLift) - PrimaryKeyButtonStyle.ledge
    }

    /// `face`, the key as drawn, in its place in the bar, where it sizes the bar's room.
    private func placed(_ face: some View) -> some View {
        face
            .padding(.horizontal, sideInset)
            // The bar's room is the resting face's, laid out on the safe area's bottom, and the
            // key is drawn down from there to its ledge's place, `ledgeLift` above the screen's
            // bottom, into the safe area; on the keyboard, up by its ledge, which so shows above
            // it: drawn down, the face went behind the keyboard's top. The bar keeps its room, so
            // the list under it doesn't move as the key is pressed. The move is an offset, never
            // the bar's height:
            // `bottomInset` is measured only after the first layout, and a bar whose height
            // followed it changed the list's inset a second time in its first frame, which SwiftUI
            // logs as an `OnScrollGeometryChange` fault.
            .padding(.bottom, -PrimaryKeyButtonStyle.ledge)
            .offset(y: drawnLower)
            .padding(.top, PrimaryKeyButtonStyle.barTop + PrimaryKeyButtonStyle.ledge)
    }

    /// The key as things stand, placed but never shown: what holds the bar's room while
    /// `keepsRoom` does.
    private var unseenKey: some View {
        placed(key(face, true).buttonStyle(.primaryKey))
    }

    /// `floating` over an unseen copy of the key it sits over, `shown` (the staged key's
    /// `KeyStage.floatingFace(for:)`) or, with no key presented, the key as things stand, so a
    /// key coming in leaves it where it is. The copy's ledge sits where the key's does,
    /// `ledgeLift` above the screen's bottom, the keyboard's inset left out, so the button stays
    /// put as the keyboard rises.
    private func floatingPlace(over shown: Face?) -> some View {
        FloatingPlace(
            key: key(shown ?? face, true).buttonStyle(.primaryKey),
            floating: floating,
            gap: PrimaryKeyButtonStyle.floatingGap,
            sides: sideInset,
            bottom: ledgeLift - bottomInset,
            // Never low over a key that shows, which it would sit on.
            isLow: floatsLow && !isPresented,
        )
    }

    func body(content: Content) -> some View {
        content
            // No band behind the key: the list's rows run on under it.
            .scrollEdgeEffectHidden(true, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                // One stack, so a key coming in and the unseen one holding its room overlap
                // rather than stack up for the transition's length.
                ZStack {
                    if isPresented {
                        StagedKey(
                            face: face,
                            isDropped: drop > 0,
                            below: bottomInset,
                        ) { shown, isOut in
                            placed(
                                key(shown, isOut)
                                    .buttonStyle(.primaryKey)
                                    .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) {
                                        $0
                                    }
                                    .modifier(KeyDrop(drop: drop))
                                    .modifier(KeySwap(isOut: isOut, drawnLower: drawnLower))
                                    .hiddenBehindDrawer(),
                            )
                        }
                        .transition(KeyBarTransition(below: bottomInset))
                    } else if keepsRoom {
                        // Only what sizes it: no bounds for the +1, and no drop or swap to run.
                        unseenKey.hidden()
                    }
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
            // Measured as `bottomInset` is but with the keyboard's inset, which is more than
            // the screen's own while the keyboard is up.
            .background {
                Color.clear.onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) {
                    keyboardInset = $0
                }
            }
            // Over the screen rather than in the bar, so it can rise above the bar's room.
            .overlayPreferenceValue(PrimaryKeyBounds.self) { key in
                GeometryReader { proxy in
                    if let key {
                        let bounds = proxy[key]
                        PlusOneBurst(trigger: plusOnes)
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
            .overlayPreferenceValue(FloatingFace<Face>.self, alignment: .bottom) { shown in
                floatingPlace(over: shown)
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

/// The key coming up from below the screen's edge, unfaded, and going back down as it fades;
/// with Reduce Motion, only fading. `below` is how far the screen runs on below the bar.
struct KeyBarTransition: Transition {
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
        let isDown = !phase.isIdentity && !reduceMotion
        let below = below
        content
            .visualEffect { content, proxy in
                content.offset(y: isDown ? proxy.size.height + below : 0)
            }
            .opacity(isFaded ? 0 : 1)
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

import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill on a ledge, label
/// centered. Pressing pushes the key down onto its ledge, which stays put, so nothing around it
/// moves, and letting go lets it back up, each in 0.06 s, easing out. Not green: green is for
/// data.
///
/// A capsule, its ends fully round, on a ledge of the same shape. A label that wraps, at the
/// largest text sizes, makes the key taller with the same round corners and straight sides
/// between them: as a capsule it went oval, and the label's first and last lines stood out past
/// its edge. At the accessibility sizes the label's side padding is smaller, so a short label, as
/// an exercise's name on the way back, stays on one line and the key a capsule; with none, a
/// label that just fit ran into the round ends.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    /// A little taller than a key, such as Add exercise.
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 56
    /// Above and below the label, inside the minimum height for one line, so a wrapped label's
    /// first and last lines stay clear of the round corners.
    @ScaledMetric(relativeTo: .title3) private var labelInset: CGFloat = 12
    /// How far the key goes down onto its ledge when pressed, and how far the ledge shows below it.
    fileprivate static let ledge: CGFloat = 4
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
    /// hidden, which a `safeAreaBar` would otherwise draw behind the bar. Its sides are as far
    /// from the screen's edges as its bottom is from the screen's bottom. Each time `plusOnes`
    /// goes up, a +1 pops off the key's top. `drop` moves the key down by that much, at least off
    /// the screen, which an animation carries it along at its own pace.
    ///
    /// `key` draws `face`, the key as things stand. A face of another `id` is another key, which
    /// the bar swaps in on its own (`KeyStage`): the one showing goes down out of the screen's
    /// bottom edge with its words as they were, then the next comes up in from it, each in
    /// `PrimaryKeyButtonStyle.swapHalf`, never two keys at once and never both words on one;
    /// with Reduce Motion, each fades. The bar keeps its room throughout, so the list under it
    /// stays put: with the bar gone between them, a list at its end moved down. The key takes
    /// no tap while it swaps. Within one id, the words change in place. A face that changes
    /// while the key is not presented comes back as the new key, with no swap. While
    /// `keepsRoom`, a key not presented still holds its room in the bar, unseen, so the list's
    /// bottom inset stays as the key goes and comes back.
    public func primaryKeyBar<Face: Equatable & Identifiable, Key: View>(
        isPresented: Bool,
        face: Face,
        keepsRoom: Bool = false,
        plusOnes: Int = 0,
        drop: CGFloat = 0,
        @ViewBuilder key: @escaping (Face) -> Key,
    ) -> some View {
        modifier(PrimaryKeyBar(
            isPresented: isPresented,
            face: face,
            keepsRoom: keepsRoom,
            plusOnes: plusOnes,
            drop: drop,
            key: key,
        ))
    }

    /// A bar whose key is always the same one, as Start alone.
    public func primaryKeyBar(
        isPresented: Bool,
        keepsRoom: Bool = false,
        plusOnes: Int = 0,
        drop: CGFloat = 0,
        @ViewBuilder key: () -> some View,
    ) -> some View {
        let key = key()
        return primaryKeyBar(
            isPresented: isPresented,
            face: OneFace(),
            keepsRoom: keepsRoom,
            plusOnes: plusOnes,
            drop: drop,
        ) { _ in key }
    }
}

/// The face of a bar with one key.
private struct OneFace: Equatable, Identifiable {
    var id: Int {
        0
    }
}

private struct PrimaryKeyBar<Face: Equatable & Identifiable, Key: View>: ViewModifier {
    let isPresented: Bool
    let face: Face
    let keepsRoom: Bool
    let plusOnes: Int
    let drop: CGFloat
    let key: (Face) -> Key

    /// Where the key is in a swap for another, from the face it showed.
    @State private var stage: KeyStage<Face>

    init(
        isPresented: Bool,
        face: Face,
        keepsRoom: Bool,
        plusOnes: Int,
        drop: CGFloat,
        key: @escaping (Face) -> Key,
    ) {
        self.isPresented = isPresented
        self.face = face
        self.keepsRoom = keepsRoom
        self.plusOnes = plusOnes
        self.drop = drop
        self.key = key
        _stage = State(initialValue: .showing(face))
    }

    /// The screen's bottom safe area, less the keyboard's, measured on the screen rather than on
    /// the key, so a key coming in has it from its first frame: measured on the key, it came in
    /// 16 pt from the sides, then narrowed to its place on the screen's next animation.
    @State private var bottomInset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The key's inset from the screen's sides: as far as its bottom is from the screen's bottom,
    /// with no home indicator as far as content is inset. At the accessibility sizes, where a key
    /// many times taller is no longer concentric with the screen's corners anyway, as far as
    /// content is inset, so its label has the width to stay on one line.
    private var sideInset: CGFloat {
        bottomInset > 0 && !dynamicTypeSize.isAccessibilitySize ? bottomInset : Spacing.md
    }

    /// `face`, the key as drawn, in its place in the bar, where it sizes the bar's room.
    private func placed(_ face: some View) -> some View {
        face
            // As far from the sides as from the bottom; with no home indicator, as far as content
            // is inset. On an iPhone 17 that is concentric with the screen's corners: its 62 pt
            // corners less the key's 28 pt radius is the 34 pt inset.
            .padding(.horizontal, sideInset)
            // The resting face, not the ledge under it, at that distance from the bottom: the ledge
            // and the pressed face sit below it, in the safe area. The bar keeps its room, so the
            // list under it doesn't move. With no safe area below, the key rises by its ledge,
            // which so stays on the screen. That rise is an offset, never the bar's height:
            // `bottomInset` is measured only after the first layout, and a bar whose height
            // followed it changed the list's inset a second time in its first frame, which SwiftUI
            // logs as an `OnScrollGeometryChange` fault.
            .padding(.bottom, -PrimaryKeyButtonStyle.ledge)
            .offset(y: bottomInset > 0 ? 0 : -PrimaryKeyButtonStyle.ledge)
            .padding(.top, Spacing.sm + PrimaryKeyButtonStyle.ledge)
    }

    func body(content: Content) -> some View {
        content
            // No band behind the key: the list's rows run on under it.
            .scrollEdgeEffectHidden(true, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                // One stack, so a key coming in and the unseen one holding its room overlap
                // rather than stack up for the transition's length.
                let shown = stage.face(for: face)
                ZStack {
                    if isPresented {
                        placed(
                            key(shown)
                                .buttonStyle(.primaryKey)
                                .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) {
                                    $0
                                }
                                .modifier(KeyDrop(drop: drop))
                                .modifier(KeySwap(isOut: stage.isOut))
                                .disabled(!stage.takesTaps)
                                .hiddenBehindDrawer(),
                        )
                        .transition(KeyBarTransition(below: bottomInset))
                        // Another key comes in afresh: one put back just after it went otherwise
                        // took up the one going, faded and below the edge, and faded in as it rose.
                        .id(shown.id)
                    } else if keepsRoom {
                        // Only what sizes it: no bounds for the +1, and no drop or swap to run.
                        placed(key(shown).buttonStyle(.primaryKey)).hidden()
                    }
                }
            }
            .onChange(of: face) { follow() }
            .onChange(of: isPresented) { follow() }
            // The swap's beats, owned by the bar: its going away, or a key no longer presented,
            // cancels them.
            .task(id: stage.isOut) { await swap() }
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
    }
}

extension PrimaryKeyBar {
    /// Follows the face and whether it is presented. Each write names its transaction, since
    /// this can run inside another change's animation, as a row's.
    private func follow() {
        var next = stage
        next.follow(face, isPresented: isPresented)
        guard next != stage else { return }
        if case .leaving = next, !stage.isOut {
            // Easing in, so it is still in sight until it clears the edge, and the next one comes
            // up straight after: easing out, it crept out of sight over its last frames.
            withAnimation(.easeIn(duration: PrimaryKeyButtonStyle.swapHalf)) { stage = next }
        } else {
            withTransaction(\.disablesAnimations, true) { stage = next }
        }
    }

    /// Once the key going is out of sight, the next one in its place below the edge, rising on a
    /// later turn of the run loop. Timed, not on the animation's completion, which came a few
    /// frames after the key had gone.
    private func swap() async {
        guard stage.isOut else { return }
        do {
            try await Task.sleep(for: .seconds(PrimaryKeyButtonStyle.swapHalf), tolerance: .zero)
        } catch {
            return
        }
        // Out of sight, the key becomes the next one with no transition of its own.
        withTransaction(\.disablesAnimations, true) { stage.advance() }
        // From out of sight: in the same update, the next key took up the old one's place.
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: PrimaryKeyButtonStyle.swapHalf)) { stage.advance() }
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

/// The key down out of sight while `isOut`, as far as its height and what lies below it, in
/// place: the bar keeps its room. No further, so the key coming in starts up as the one going
/// clears the edge: with 8 pt more, the two halves had frames with no key between them. Unfaded
/// both ways: faded going, it was all but gone three frames before it cleared the edge. With
/// Reduce Motion it stays put and fades each way. Measured as it is drawn, so a
/// key that starts out of sight is out of sight from its first frame.
private struct KeySwap: ViewModifier, Animatable {
    /// How far out the key is, 0 to 1, which an animation runs through.
    var progress: CGFloat

    init(isOut: Bool) {
        progress = isOut ? 1 : 0
    }

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let progress = progress
        let moves = !reduceMotion
        content
            .visualEffect { content, proxy in
                content.offset(y: moves
                    ? progress * (proxy.size.height + proxy.safeAreaInsets.bottom)
                    : 0)
            }
            .opacity(reduceMotion ? 1 - progress : 1)
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

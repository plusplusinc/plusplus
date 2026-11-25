import SwiftUI

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
    /// screen's. Each time `finishes` goes up, the finish's "++" pops off the key's top
    /// (`FinishBurst`); the key holds still under it, so it plays at the key's bounds as they
    /// are drawn, unseen with no key. `drop` moves the key down by that much, at least off the
    /// screen, which an animation carries it along at its own
    /// pace. The keyboard covers the key, and the screen with it, rather than lifting them.
    ///
    /// `floating`, a button drawn in the `floating` style, floats above the key's right end, its
    /// right edge on the key's and 16 pt above the key's top, whether the key shows or not: with
    /// none, it is where it is above a key of one line, so a key coming in leaves it where it is.
    /// While `floatsLow`, as on a screen with nothing for the key to do yet, it sits low instead,
    /// its bottom where the key's ledge's bottom would be, and rises above the key, or comes
    /// back down, on the update that changes `floatsLow`, with the key's rise or drop when the
    /// same update presents or takes it away. The caller keeps it off over a key that shows, and
    /// may set it as a key rides down by `drop`, in its own update, on its own curve.
    /// It takes no room from the content: a list under it leaves `FloatingButtonRoom` at its end.
    ///
    /// `key` draws `face`, the key as things stand. A face of another `id` is another key, which
    /// the bar swaps in on its own (`KeyStage`): the one showing goes down out of the screen's
    /// bottom edge with its words as they were, then the next comes up in from it, each in
    /// `PrimaryKeyButtonStyle.swapHalf`, never two keys at once and never both words on one;
    /// with Reduce Motion, each fades. The floating button goes down and comes back up with
    /// them, as one piece; with Reduce Motion it stays put. The bar keeps its room throughout,
    /// so the list under it
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
        finishes: Int = 0,
        drop: CGFloat = 0,
        floatsLow: Bool = false,
        @ViewBuilder key: @escaping (Face, _ isOut: Bool) -> Key,
        @ViewBuilder floating: () -> some View = { EmptyView() },
    ) -> some View {
        modifier(PrimaryKeyBar(
            isPresented: isPresented,
            face: face,
            keepsRoom: keepsRoom,
            finishes: finishes,
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
        finishes: Int = 0,
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
            finishes: finishes,
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
    let finishes: Int
    let drop: CGFloat
    let floatsLow: Bool
    let key: (Face, _ isOut: Bool) -> Key
    let floating: Floating

    /// The screen's bottom safe area, measured on the screen rather than on the key, so a key
    /// coming in has it from its first frame: measured on the key, it came in 16 pt from the
    /// sides, then narrowed to its place on the screen's next animation.
    @State private var bottomInset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The key's inset from the screen's sides: `lowInset`, and with no home indicator, as far as
    /// content is inset. At the accessibility sizes, as far as content is inset, so its label
    /// has the width to stay on one line.
    private var sideInset: CGFloat {
        KeyInsets.side(bottomInset: bottomInset, dynamicTypeSize: dynamicTypeSize)
    }

    private var ledgeLift: CGFloat {
        KeyInsets.ledgeLift(bottomInset: bottomInset)
    }

    /// How far below its place in the bar the key is drawn: down to its ledge's place.
    private var drawnLower: CGFloat {
        bottomInset - ledgeLift - PrimaryKeyButtonStyle.ledge
    }

    /// How far a swap takes the key down past its own height (`KeySwap`): to the screen's bottom
    /// edge, less `drawnLower`.
    private var swapBelow: CGFloat {
        ledgeLift - drawnLower
    }

    /// `face`, the key as drawn, in its place in the bar, where it sizes the bar's room.
    private func placed(_ face: some View) -> some View {
        face
            .padding(.horizontal, sideInset)
            // The bar's room is the resting face's, laid out on the safe area's bottom, and the
            // key is drawn down from there to its ledge's place, `ledgeLift` above the screen's
            // bottom, into the safe area. The bar keeps its room, so the list under it doesn't
            // move as the key is pressed. The move is an offset, never the bar's height:
            // `bottomInset` is measured only after the first layout, and a bar whose height
            // followed it changed the list's inset a second time in its first frame, which SwiftUI
            // logs as an `OnScrollGeometryChange` fault.
            .padding(.bottom, -PrimaryKeyButtonStyle.ledge)
            .offset(y: drawnLower)
            .padding(.top, PrimaryKeyButtonStyle.barTop + PrimaryKeyButtonStyle.ledge)
    }

    /// The key as things stand, placed but never shown: what holds the bar's room while
    /// `keepsRoom` does, and where a finish's "++" pops from with no key shown, as through a
    /// set's "Start in".
    private var unseenKey: some View {
        placed(
            key(face, true)
                .buttonStyle(.primaryKey)
                .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) { $0 },
        )
    }

    /// `floating` over an unseen copy of `shown` (`KeyStage.floatingFace(for:)`), else the live
    /// key, its ledge `ledgeLift` up, going down and up with a swap's keys, as far along as
    /// they are drawn (`FloatingOver.dip`) and as far as they go.
    private func floatingPlace(over shown: FloatingOver<Face>?) -> some View {
        let over = shown?.face ?? face
        return FloatingPlace(
            key: key(over, true).buttonStyle(.primaryKey),
            floating: floating,
            gap: PrimaryKeyButtonStyle.floatingGap,
            sides: sideInset,
            bottom: ledgeLift - bottomInset,
            isLow: floatsLow,
            dip: shown?.dip ?? 0,
            swapBelow: swapBelow,
            keyID: AnyHashable(over.id),
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
                                    .modifier(KeySwap<Face>(isOut: isOut, below: swapBelow))
                                    .hiddenBehindDrawer(),
                            )
                        }
                        .transition(KeyBarTransition(below: bottomInset))
                    } else if keepsRoom {
                        // Its room and the burst's place, with no drop or swap to run.
                        unseenKey.hidden()
                    }
                }
            }
            .background {
                Color.clear.onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) {
                    bottomInset = $0
                }
            }
            // Over the screen rather than in the bar, so it can rise above the bar's room.
            .overlayPreferenceValue(PrimaryKeyBounds.self) { key in
                GeometryReader { proxy in
                    if let key {
                        let bounds = proxy[key]
                        FinishBurst(trigger: finishes)
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
            // The keyboard covers the key rather than lifting it: the screen and its bar stay
            // where they are as it rises. Everything above measures inside this, where the
            // keyboard's inset is taken away.
            .ignoresSafeArea(.keyboard, edges: .bottom)
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

/// Where the primary key is, for the "++" that pops off its top.
private struct PrimaryKeyBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

#Preview("Bar") {
    Color.pp(.background)
        .ignoresSafeArea()
        .primaryKeyBar(isPresented: true) {
            Button("Start", systemImage: "play.fill") { }
        }
}

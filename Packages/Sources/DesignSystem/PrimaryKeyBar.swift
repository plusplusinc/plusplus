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
    /// are drawn, unseen with no key. While `drop` is above 0 the key rides down out of sight, at
    /// the pace of a key going down in a swap whatever the update's animation (`KeyRide`), and
    /// takes no tap. The keyboard covers the key, and the screen with it, rather than lifting them.
    ///
    /// `floating`, a button drawn in the `floating` style, floats above the key's right end, its
    /// right edge on the key's and 16 pt above the key's top, and rides on the key as one piece
    /// (`KeyReach.floatingLift`): down and up with a swap, down as the key is taken away or
    /// ridden down, up as it comes in. Once the key has gone further down than the button's low
    /// place, its bottom where the key's ledge's bottom is, the button stays there: so it sits
    /// low wherever no key is in sight, as on a screen with nothing for the key to do yet. With
    /// Reduce Motion it stays put through a swap and fades from one place into the other as a
    /// key goes or comes. It takes no room from the content: a list under it leaves
    /// `FloatingButtonRoom` at its end.
    ///
    /// `key` draws `face`, the key as things stand. A face of another `id` is another key, which
    /// the bar swaps in on its own (`KeyTray`): the one showing goes down out of the screen's
    /// bottom edge with its words as they were, then the next comes up in from it, each in
    /// `PrimaryKeyButtonStyle.swapHalf`, never two keys at once and never both words on one;
    /// with Reduce Motion, each fades. The bar keeps its room throughout, so the list under it
    /// stays put: with the bar gone between them, a list at its end moved down. While it swaps,
    /// `key` is told it is out (`isOut`), and its action does nothing then: the key stays
    /// enabled, as VoiceOver reads it, rather than dimmed for the swap's length. Within one id,
    /// the words change in place. A key taken away, or ridden out of sight by `drop`, goes with
    /// the words it had; back, it is the key `face` is then, with no swap, rising under the
    /// animation that brings it back. While `keepsRoom`, a key not presented still holds its room
    /// in the bar, unseen, so the list's bottom inset stays as the key goes and comes back.
    public func primaryKeyBar<Face: Equatable & Identifiable, Key: View>(
        isPresented: Bool,
        face: Face,
        keepsRoom: Bool = false,
        finishes: Int = 0,
        drop: CGFloat = 0,
        @ViewBuilder key: @escaping (Face, _ isOut: Bool) -> Key,
        @ViewBuilder floating: () -> some View = { EmptyView() },
    ) -> some View {
        modifier(PrimaryKeyBar(
            isPresented: isPresented,
            face: face,
            keepsRoom: keepsRoom,
            finishes: finishes,
            drop: drop,
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

/// The bar's `KeyTray`, held by reference so the bar follows its inputs as it draws them.
private final class TrayBox<Face: Equatable & Identifiable> {
    var tray: KeyTray<Face>

    init(_ inputs: KeyTray<Face>.Inputs) {
        tray = KeyTray(inputs)
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
    let key: (Face, _ isOut: Bool) -> Key
    let floating: Floating

    /// The screen's bottom safe area, measured on the screen rather than on the key, so a key
    /// coming in has it from its first frame: measured on the key, it came in 16 pt from the
    /// sides, then narrowed to its place on the screen's next animation.
    @State private var bottomInset: CGFloat = 0
    /// Where the key is: followed in `body`, the first place the bar sees its inputs, so no input
    /// waits on a reaction. A reaction lost a change: SwiftUI skips a second change within
    /// one frame (2026-11-15), and a key put back before its reaction ran rose as the key going.
    @State private var box: TrayBox<Face>
    /// The swap whose key going is drawn all the way down, which the tray turns on as it follows
    /// (`KeySwapDown`).
    @State private var down: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isPresented: Bool,
        face: Face,
        keepsRoom: Bool,
        finishes: Int,
        drop: CGFloat,
        key: @escaping (Face, _ isOut: Bool) -> Key,
        floating: Floating,
    ) {
        self.isPresented = isPresented
        self.face = face
        self.keepsRoom = keepsRoom
        self.finishes = finishes
        self.drop = drop
        self.key = key
        self.floating = floating
        _box = State(initialValue: TrayBox(KeyTray.Inputs(
            face: face,
            isPresented: isPresented,
            isDropped: drop > 0,
        )))
    }

    private var inputs: KeyTray<Face>.Inputs {
        KeyTray.Inputs(face: face, isPresented: isPresented, isDropped: drop > 0)
    }

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

    /// How far each move takes the key down: a swap to the screen's bottom edge, less
    /// `drawnLower`.
    private var reach: KeyReach {
        KeyReach(
            swapBelow: ledgeLift - drawnLower,
            bottomInset: bottomInset,
            gap: PrimaryKeyButtonStyle.floatingGap,
        )
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
    /// set's "Start in". A second copy, since the key taken away goes with its own words while
    /// the room is already the next key's, which at the largest sizes is another height.
    private var unseenKey: some View {
        placed(
            key(face, true)
                .buttonStyle(.primaryKey)
                .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) { $0 },
        )
    }

    /// The one key, always there: drawn as the tray has it, down by its depth, and while not
    /// presented, out of sight with no room, no taps, and nothing for VoiceOver.
    private func trayKey(_ drawn: KeyTray<Face>.Drawn) -> some View {
        let isPresented = isPresented
        let inSight = inputs.inSight
        return placed(
            key(drawn.face, drawn.isOut || !inSight)
                .buttonStyle(.primaryKey)
                // Another key in place of the one drawn, at once under any animation: the move is
                // the tray's.
                .transition(.identity)
                .id(drawn.face.id)
                .transaction(value: drawn.face.id) { $0.animation = nil }
                .anchorPreference(key: PrimaryKeyBounds.self, value: .bounds) {
                    isPresented ? $0 : nil
                }
                .modifier(KeyTravel(away: drawn.away, reach: reach, isPresented: isPresented))
                .keySwap(drawn.swap, reach: reach)
                // At its own pace, outside the screen's animation.
                .keyRide(drawn.ride, reach: reach)
                .hiddenBehindDrawer()
                .accessibilityShown(inSight),
        )
        .fixedSize(horizontal: false, vertical: true)
        // Its resting place stays put as its room goes.
        .frame(height: isPresented ? nil : 0, alignment: .bottom)
        // An offset drawn moves nothing of where taps land, and the low floating button is there.
        .allowsHitTesting(inSight)
    }

    /// `floating` riding on the key as `KeyTravel` draws it, its height from its bounds.
    private func floatingPlace(on drawn: TrayDrawn) -> some View {
        let inSight = inputs.inSight
        return GeometryReader { proxy in
            let height = drawn.bounds.map { proxy[$0].height } ?? 0
            FloatingPlace(
                floating: floating,
                sides: sideInset,
                bottom: ledgeLift - bottomInset,
                lift: reach.floatingLift(
                    drawn.parts,
                    height: height,
                    reduceMotion: reduceMotion,
                    inSight: inSight,
                ),
                isLow: !inSight,
            )
        }
    }

    func body(content: Content) -> some View {
        let inputs = inputs
        box.tray.follow(inputs, down: down)
        let drawn = box.tray.drawn(for: inputs)
        return content
            // No band behind the key: the list's rows run on under it.
            .scrollEdgeEffectHidden(true, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                // One stack, so the key and the unseen one holding its room overlap.
                ZStack(alignment: .bottom) {
                    trayKey(drawn)
                    if !isPresented, keepsRoom {
                        // Its room and the burst's place.
                        unseenKey.hidden()
                    }
                }
            }
            // The swap turns as the bar next follows, whatever update that is: in this one, if
            // nothing else comes first.
            .onPreferenceChange(KeySwapDown.self) { down = $0 }
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
            .overlayPreferenceValue(KeyTrayDrawn.self) { floatingPlace(on: $0) }
            // The keyboard covers the key rather than lifting it: the screen and its bar stay
            // where they are as it rises. Everything above measures inside this, where the
            // keyboard's inset is taken away.
            .ignoresSafeArea(.keyboard, edges: .bottom)
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

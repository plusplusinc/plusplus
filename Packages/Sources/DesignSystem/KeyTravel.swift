import SwiftUI

extension Animation {
    /// A key going down and out of sight, the first half of a swap: easing in, so it is still in
    /// sight until it clears the edge.
    public static let keyDrop = Animation.easeIn(duration: PrimaryKeyButtonStyle.swapHalf)
    /// A key coming up into place, the second half of a swap.
    public static let keyRise = Animation.smooth(duration: PrimaryKeyButtonStyle.swapHalf)
}

/// The bar's key drawn down from its place by its one depth (`KeyReach.depth`), each part run by
/// the animation of the update that changed its target: a swap's halves, and the screen taking
/// the key away or bringing it back. The screen riding it down is `KeyRide`'s, at its own pace,
/// which adds its part to what goes to the floating button. Its height is the one drawn that
/// frame, so a key that starts
/// out of sight is out of sight from its first frame. A swap takes it down to the screen's
/// bottom edge and no further, so the key coming in starts up as the one going clears the edge:
/// with 8 pt more, the two halves had frames with no key between them.
///
/// Unfaded through a swap, and coming in: faded going, it was all but gone three frames before
/// it cleared the edge. Taken away, it fades as it goes. With Reduce Motion a swap and a key
/// taken away or brought back stay put and fade each way. The parts as drawn, and the key's
/// bounds, go up to the floating button (`KeyTrayDrawn`), which rides on them.
struct KeyTravel: ViewModifier, Animatable {
    /// How far each move has the key down, 0 to 1, which an animation runs through.
    var parts: KeyReach.Parts
    let reach: KeyReach
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>,
    > {
        get {
            AnimatablePair(
                AnimatablePair(parts.leave, parts.arrive),
                AnimatablePair(parts.away, parts.drop),
            )
        }
        set {
            parts = KeyReach.Parts(
                leave: newValue.first.first,
                arrive: newValue.first.second,
                away: newValue.second.first,
                drop: newValue.second.second,
            )
        }
    }

    func body(content: Content) -> some View {
        let parts = parts
        let reach = reach
        let reduceMotion = reduceMotion
        let isPresented = isPresented
        let opacity: CGFloat = isPresented ? (reduceMotion ? 1 - parts.swap : 1) : 0
        content
            .anchorPreference(key: KeyTrayDrawn.self, value: .bounds) {
                TrayDrawn(bounds: $0, parts: parts)
            }
            .visualEffect { content, proxy in
                content.offset(
                    y: reach.depth(parts, height: proxy.size.height, reduceMotion: reduceMotion),
                )
            }
            // A key comes in unfaded, so its fade is not animated back in.
            .transaction { transaction in
                if isPresented, !reduceMotion {
                    transaction.animation = nil
                }
            } body: {
                $0.opacity(opacity)
            }
    }
}

/// The bar's key ridden down out of sight by the screen (`drop`), at the pace of a key going down
/// in a swap (`keyDrop`), whatever the screen's own animation: ridden on the list's grow, a
/// screen's height on its curve, Start was gone in three frames, much faster than any other key
/// going down. Coming back is the screen's, with no animation. Adds its part to what
/// `KeyTravel` sends the floating button, so the button rides it too.
struct KeyRide: ViewModifier, Animatable {
    /// How far along the ride the key is, 0 to 1.
    var drop: CGFloat
    let reach: KeyReach

    nonisolated var animatableData: CGFloat {
        get { drop }
        set { drop = newValue }
    }

    func body(content: Content) -> some View {
        let drop = drop
        let reach = reach
        content
            .transformPreference(KeyTrayDrawn.self) { $0.parts.drop = drop }
            .visualEffect { content, proxy in
                content.offset(y: reach.depth(
                    KeyReach.Parts(swap: 0, away: 0, drop: drop),
                    height: proxy.size.height,
                ))
            }
    }
}

extension View {
    /// The key ridden down by `drop`, 0 or 1, at a key's own pace going down (`KeyRide`).
    func keyRide(_ drop: CGFloat, reach: KeyReach) -> some View {
        // On the update that changes it alone: the key's other parts don't change then.
        modifier(KeyRide(drop: drop, reach: reach)).animation(.keyDrop, value: drop)
    }
}

/// The bar's key as `KeyTravel` draws it: its bounds at rest and how far down each move has it.
struct TrayDrawn: Equatable {
    var bounds: Anchor<CGRect>?
    var parts = KeyReach.Parts(swap: 0, away: 0, drop: 0)
}

/// Where the bar's key is, for the floating button that rides on it.
struct KeyTrayDrawn: PreferenceKey {
    static let defaultValue = TrayDrawn()

    static func reduce(value: inout TrayDrawn, nextValue: () -> TrayDrawn) {
        if value.bounds == nil {
            value = nextValue()
        }
    }
}

/// The bar's floating button going low into the key's row as the key leaves: it takes no tap from
/// then until it has rested there for a whole swap, `settlesLow`, so a second tap meant for the
/// key, or for +15 s beside it, never lands on the button arriving where they were. Going back
/// up it takes taps at once, as a key coming in does. Not on first showing low, as on an empty
/// workout, where nothing was there before it.
struct LowSettle: ViewModifier {
    let isLow: Bool
    @State private var isSettling = false

    /// From the change: the slowest move that takes the keys away (`SetMotion.restSwap`, `roll`)
    /// and then a swap's two halves at rest.
    static var settlesLow: Double {
        SetMotion.roll + 2 * PrimaryKeyButtonStyle.swapHalf
    }

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isSettling)
            .onChange(of: isLow) { _, isLow in isSettling = isLow }
            .task(id: isSettling) {
                guard isSettling else { return }
                try? await Task.sleep(for: .seconds(Self.settlesLow), tolerance: .zero)
                if !Task.isCancelled {
                    isSettling = false
                }
            }
    }
}

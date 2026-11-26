import SwiftUI

extension Animation {
    /// A key going down and out of sight, the first half of a swap: easing in, so it is still in
    /// sight until it clears the edge.
    public static let keyDrop = Animation.easeIn(duration: PrimaryKeyButtonStyle.swapHalf)
    /// A key coming up into place, the second half of a swap.
    public static let keyRise = Animation.smooth(duration: PrimaryKeyButtonStyle.swapHalf)
}

/// The bar's key drawn down from its place as the screen takes it away or brings it back (`away`,
/// in `KeyReach.depth`), run by the animation of the update that changed it. A swap's part is
/// `KeySwap`'s and the screen riding it down `KeyRide`'s, each at its own pace, each adding its
/// part to what goes to the floating button. Its height is the one drawn that frame, so a key that
/// starts out of sight is out of sight from its first frame.
///
/// Taken away, it fades as it goes; it comes in unfaded. With Reduce Motion a key taken away or
/// brought back stays put and fades each way. The part as drawn, and the key's bounds, go up to
/// the floating button (`KeyTrayDrawn`), which rides on them.
struct KeyTravel: ViewModifier, Animatable {
    /// How far the screen has the key taken away, 0 to 1, which an animation runs through.
    var away: CGFloat
    let reach: KeyReach
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated var animatableData: CGFloat {
        get { away }
        set { away = newValue }
    }

    func body(content: Content) -> some View {
        let parts = KeyReach.Parts(away: away)
        let reach = reach
        let reduceMotion = reduceMotion
        let isPresented = isPresented
        return content
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
                $0.opacity(isPresented ? 1 : 0)
            }
    }
}

/// A swap's part of the bar's key's depth, and how it runs there (`KeyTray.Drawn.swap`).
struct SwapDrawn: Equatable {
    /// Which swap it is, so each swap's drop drawn down is news to the bar (`KeySwapDown`).
    var number: Int
    var pace: Pace

    /// 1 while the key is out in the swap, going down, 0 otherwise.
    var depth: CGFloat {
        pace == .drop ? 1 : 0
    }

    /// What runs it: down at `keyDrop` while leaving, back up at `keyRise` once showing, whatever
    /// animation the update that turned it carries: a turn landing in the update of a change with
    /// no animation, as Pause, stood the next key at rest at once (2026-11-25). Away, the
    /// update's own, as it runs the key going.
    enum Pace: Equatable {
        case drop
        case rise
        case update

        var animation: Animation? {
            switch self {
            case .drop: .keyDrop
            case .rise: .keyRise
            case .update: nil
            }
        }
    }
}

/// The bar's key in a swap: down to the screen's bottom edge and no further, so the key coming in
/// starts up as the one going clears the edge: with 8 pt more, the two halves had frames with no
/// key between them. Unfaded through it: faded going, it was all but gone three frames before it
/// cleared the edge. With Reduce Motion it stays put and fades each way. Its drop drawn all the
/// way down goes up to the bar as the swap's number (`KeySwapDown`), which turns it.
struct KeySwap: ViewModifier, Animatable {
    var depth: CGFloat
    let number: Int
    let reach: KeyReach

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func body(content: Content) -> some View {
        let depth = depth
        let parts = KeyReach.Parts(swap: depth)
        let reach = reach
        let reduceMotion = reduceMotion
        return content
            // The key's own changes keep the update's animation; the pace is the swap's alone.
            .transaction { transaction in
                if let update = transaction[UpdateAnimation.self] {
                    transaction.animation = update
                }
            }
            .transformPreference(KeyTrayDrawn.self) { $0.parts.swap = depth }
            .preference(key: KeySwapDown.self, value: depth >= 1 ? number : nil)
            .visualEffect { content, proxy in
                content.offset(
                    y: reach.depth(parts, height: proxy.size.height, reduceMotion: reduceMotion),
                )
            }
            .opacity(reduceMotion ? 1 - depth : 1)
    }
}

extension View {
    /// The key in a swap as `swap` has it, run at the swap's own pace whatever the update's
    /// animation (`SwapDrawn.Pace`).
    func keySwap(_ swap: SwapDrawn, reach: KeyReach) -> some View {
        // On the update that moves it; `KeySwap` hands the update's own back to the key inside.
        modifier(KeySwap(depth: swap.depth, number: swap.number, reach: reach))
            .transaction(value: swap.depth) { transaction in
                if let animation = swap.pace.animation {
                    transaction[UpdateAnimation.self] = .some(transaction.animation)
                    transaction.animation = animation
                }
            }
    }
}

/// The animation of the update a swap's pace replaced, for what the key draws inside it.
private struct UpdateAnimation: TransactionKey {
    static let defaultValue: Animation?? = nil
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
                    KeyReach.Parts(drop: drop),
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
    var parts = KeyReach.Parts()
}

/// Which swap's key going is all the way down as drawn, its animated part at its target, so the
/// bar turns the swap on the frame the drop ends: read from the animation itself, as
/// `listResizes(_:)` does. Timed, the drop lost its last two frames, 28 pt; and `withAnimation`'s
/// completion can run before the first frame, or frames after the motion stops. A number rather
/// than a yes, so a swap that starts with the key already drawn down, as one in the update its
/// last swap turned in, is news all the same: as a yes, nothing would change.
struct KeySwapDown: PreferenceKey {
    static let defaultValue: Int? = nil

    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = value ?? nextValue()
    }
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
